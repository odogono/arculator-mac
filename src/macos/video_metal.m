/*Arculator - Metal video backend for macOS
  Replaces video_sdl2.c with native Metal rendering.*/
#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/CAMetalLayer.h>

#include <stdio.h>
#include "arc.h"
#include "plat_video.h"
#include "vidc.h"
#include "video.h"
#include "macos/macos_util.h"

#define TEXTURE_SIZE 2048

static id<MTLDevice> metal_device;
static id<MTLCommandQueue> metal_command_queue;
static id<MTLRenderPipelineState> metal_pipeline_state;
static id<MTLTexture> metal_texture;
static id<MTLSamplerState> metal_sampler_nearest;
static id<MTLSamplerState> metal_sampler_linear;
static CAMetalLayer *metal_layer;
static NSView *metal_host_view;
static NSWindow *metal_window;
static int metal_owns_layer;

/*Cached view dimensions, updated from the main thread by
  video_renderer_update_layout() so that the render thread
  can read them without a synchronous dispatch.*/
static int cached_view_w;
static int cached_view_h;
static CGFloat cached_backing_scale = 1.0;

int selected_video_renderer;

/*Destination rect for the current frame, set by video_renderer_update().*/
typedef struct metal_rect_t
{
	int x, y, w, h;
} metal_rect_t;

static metal_rect_t texture_rect;

static int create_metal_resources(void)
{
	@autoreleasepool {
		/*Load the compiled Metal shader library from the app bundle.*/
		NSURL *libURL = [[NSBundle mainBundle] URLForResource:@"ArculatorBootstrap"
							 withExtension:@"metallib"];
		if (!libURL)
		{
			rpclog("Metal: could not find ArculatorBootstrap.metallib in bundle\n");
			return 0;
		}

		NSError *error = nil;
		id<MTLLibrary> library = [metal_device newLibraryWithURL:libURL error:&error];
		if (!library)
		{
			rpclog("Metal: failed to load metallib: %s\n",
				[[error localizedDescription] UTF8String]);
			return 0;
		}

		id<MTLFunction> vertexFunc = [library newFunctionWithName:@"arculator_passthrough_vertex"];
		id<MTLFunction> fragmentFunc = [library newFunctionWithName:@"arculator_passthrough_fragment"];
		if (!vertexFunc || !fragmentFunc)
		{
			rpclog("Metal: could not find shader functions\n");
			return 0;
		}

		/*Render pipeline.*/
		MTLRenderPipelineDescriptor *pipeDesc = [[MTLRenderPipelineDescriptor alloc] init];
		pipeDesc.vertexFunction = vertexFunc;
		pipeDesc.fragmentFunction = fragmentFunc;
		pipeDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

		metal_pipeline_state = [metal_device newRenderPipelineStateWithDescriptor:pipeDesc
										   error:&error];
		if (!metal_pipeline_state)
		{
			rpclog("Metal: failed to create pipeline state: %s\n",
				[[error localizedDescription] UTF8String]);
			return 0;
		}

		/*Backing texture: 2048x2048 BGRA8, matching BITMAP pixel format.*/
		MTLTextureDescriptor *texDesc =
			[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
									  width:TEXTURE_SIZE
									 height:TEXTURE_SIZE
								      mipmapped:NO];
		texDesc.usage = MTLTextureUsageShaderRead;
		texDesc.storageMode = MTLStorageModeManaged;

		metal_texture = [metal_device newTextureWithDescriptor:texDesc];
		if (!metal_texture)
		{
			rpclog("Metal: failed to create backing texture\n");
			return 0;
		}

		rpclog("Metal: resources created successfully\n");
		return 1;
	}
}

static void create_samplers(void)
{
	@autoreleasepool {
		MTLSamplerDescriptor *desc = [[MTLSamplerDescriptor alloc] init];
		desc.sAddressMode = MTLSamplerAddressModeClampToEdge;
		desc.tAddressMode = MTLSamplerAddressModeClampToEdge;

		desc.minFilter = MTLSamplerMinMagFilterNearest;
		desc.magFilter = MTLSamplerMinMagFilterNearest;
		metal_sampler_nearest = [metal_device newSamplerStateWithDescriptor:desc];

		desc.minFilter = MTLSamplerMinMagFilterLinear;
		desc.magFilter = MTLSamplerMinMagFilterLinear;
		metal_sampler_linear = [metal_device newSamplerStateWithDescriptor:desc];
	}
}

int video_renderer_init(void *main_window)
{
	@autoreleasepool {
		__block int init_ok = 1;

		rpclog("video_renderer_init() [Metal]\n");

		run_on_main_thread(^{
			metal_host_view = (__bridge NSView *)main_window;
			metal_window = [metal_host_view window];
			if (!metal_host_view || !metal_window)
			{
				rpclog("Metal: host view/window unavailable\n");
				init_ok = 0;
			}
		});

		if (!init_ok)
			return 0;

		if ([metal_host_view isKindOfClass:[MTKView class]])
			metal_device = [(MTKView *)metal_host_view device];
		if (!metal_device)
			metal_device = MTLCreateSystemDefaultDevice();
		if (!metal_device)
		{
			rpclog("Metal: MTLCreateSystemDefaultDevice failed\n");
			return 0;
		}

		metal_command_queue = [metal_device newCommandQueue];

		run_on_main_thread(^{
			if ([metal_host_view isKindOfClass:[MTKView class]])
			{
				MTKView *mtk_view = (MTKView *)metal_host_view;
				mtk_view.device = metal_device;
				mtk_view.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
				mtk_view.framebufferOnly = YES;
				mtk_view.paused = YES;
				mtk_view.enableSetNeedsDisplay = NO;
				metal_layer = (CAMetalLayer *)[mtk_view layer];
				metal_owns_layer = 0;
			}
			else
			{
				metal_layer = nil;
				if ([[metal_host_view layer] isKindOfClass:[CAMetalLayer class]])
				{
					metal_layer = (CAMetalLayer *)[metal_host_view layer];
					metal_owns_layer = 0;
				}
				else
				{
					metal_layer = [CAMetalLayer layer];
					metal_owns_layer = 1;
					[metal_host_view setWantsLayer:YES];
					[metal_host_view setLayer:metal_layer];
				}
			}

			metal_layer.device = metal_device;
			metal_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
			metal_layer.framebufferOnly = YES;
			metal_layer.contentsScale = [metal_window backingScaleFactor];
			metal_layer.frame = metal_host_view.bounds;
			metal_layer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;

			cached_backing_scale = [metal_window backingScaleFactor];
			cached_view_w = (int)metal_host_view.bounds.size.width;
			cached_view_h = (int)metal_host_view.bounds.size.height;
		});

		/*Create samplers, pipeline, and texture.*/
		create_samplers();

		if (!create_metal_resources())
			return 0;

		rpclog("Metal: video initialized\n");
		return 1;
	}
}

int video_renderer_reinit(void *main_window)
{
	@autoreleasepool {
		rpclog("video_renderer_reinit() [Metal]\n");

		metal_texture = nil;
		metal_pipeline_state = nil;

		return create_metal_resources();
	}
}

void video_renderer_close()
{
	@autoreleasepool {
		rpclog("video_renderer_close() [Metal]\n");

		metal_texture = nil;
		metal_pipeline_state = nil;
		metal_sampler_nearest = nil;
		metal_sampler_linear = nil;
		metal_command_queue = nil;
		metal_device = nil;

		if (metal_host_view && metal_owns_layer)
		{
			run_on_main_thread(^{
				[metal_host_view setLayer:nil];
			});
		}
		metal_owns_layer = 0;
		metal_host_view = nil;
		metal_window = nil;
		metal_layer = nil;
	}
}

/*Called from the main thread to refresh cached view dimensions
  and update CAMetalLayer geometry when the window resizes.*/
void video_renderer_update_layout(void)
{
	if (!metal_host_view || !metal_window || !metal_layer)
		return;

	NSSize sz = metal_host_view.bounds.size;
	CGFloat sc = [metal_window backingScaleFactor];

	if ((int)sz.width == cached_view_w &&
	    (int)sz.height == cached_view_h &&
	    sc == cached_backing_scale)
		return;

	cached_view_w = (int)sz.width;
	cached_view_h = (int)sz.height;
	cached_backing_scale = sc;

	metal_layer.contentsScale = sc;
	metal_layer.frame = metal_host_view.bounds;
	metal_layer.drawableSize = CGSizeMake(sz.width * sc, sz.height * sc);
}

/*Update display texture from memory bitmap src.
  Bounds-checking logic preserved from video_sdl2.c.*/
void video_renderer_update(BITMAP *src, int src_x, int src_y, int dest_x, int dest_y, int w, int h)
{
	LOG_VIDEO_FRAMES("video_renderer_update: src=%i,%i dest=%i,%i size=%i,%i\n", src_x,src_y, dest_x,dest_y, w,h);
	texture_rect.x = dest_x;
	texture_rect.y = dest_y;
	texture_rect.w = w;
	texture_rect.h = h;

	if (src_x < 0)
	{
		texture_rect.w += src_x;
		src_x = 0;
	}
	if (src_x > 2047)
		return;
	if ((src_x + texture_rect.w) > 2047)
		texture_rect.w = 2048 - src_x;

	if (src_y < 0)
	{
		texture_rect.h += src_y;
		src_y = 0;
	}
	if (src_y > 2047)
		return;
	if ((src_y + texture_rect.h) > 2047)
		texture_rect.h = 2048 - src_y;

	if (texture_rect.x < 0)
	{
		texture_rect.w += texture_rect.x;
		texture_rect.x = 0;
	}
	if (texture_rect.x > 2047)
		return;
	if ((texture_rect.x + texture_rect.w) > 2047)
		texture_rect.w = 2048 - texture_rect.x;

	if (texture_rect.y < 0)
	{
		texture_rect.h += texture_rect.y;
		texture_rect.y = 0;
	}
	if (texture_rect.y > 2047)
		return;
	if ((texture_rect.y + texture_rect.h) > 2047)
		texture_rect.h = 2048 - texture_rect.y;

	if (texture_rect.w <= 0 || texture_rect.h <= 0)
		return;

	if (!metal_texture)
		return;

	LOG_VIDEO_FRAMES("Metal replaceRegion (%d, %d)+(%d, %d) from src (%d, %d) w %d\n",
		texture_rect.x, texture_rect.y,
		texture_rect.w, texture_rect.h,
		src_x, src_y, src->w);

	MTLRegion region = MTLRegionMake2D(texture_rect.x, texture_rect.y,
					   texture_rect.w, texture_rect.h);
	[metal_texture replaceRegion:region
			 mipmapLevel:0
			   withBytes:&((uint32_t *)src->dat)[src_y * src->w + src_x]
			 bytesPerRow:src->w * 4];
}

/*Compute destination rect for fullscreen scaling.
  Ported from sdl_scale() in video_sdl2.c.*/
static void metal_scale(int scale, int win_w, int win_h, metal_rect_t *dst, int content_w, int content_h)
{
	double t, b, l, r;
	int ratio_w, ratio_h;

	switch (scale)
	{
		case FULLSCR_SCALE_43:
		t = 0;
		b = win_h;
		l = (win_w / 2) - ((win_h * 4) / (3 * 2));
		r = (win_w / 2) + ((win_h * 4) / (3 * 2));
		if (l < 0)
		{
			l = 0;
			r = win_w;
			t = (win_h / 2) - ((win_w * 3) / (4 * 2));
			b = (win_h / 2) + ((win_w * 3) / (4 * 2));
		}
		break;
		case FULLSCR_SCALE_SQ:
		t = 0;
		b = win_h;
		l = (win_w / 2) - ((win_h * content_w) / (content_h * 2));
		r = (win_w / 2) + ((win_h * content_w) / (content_h * 2));
		if (l < 0)
		{
			l = 0;
			r = win_w;
			t = (win_h / 2) - ((win_w * content_h) / (content_w * 2));
			b = (win_h / 2) + ((win_w * content_h) / (content_w * 2));
		}
		break;
		case FULLSCR_SCALE_INT:
		ratio_w = win_w / content_w;
		ratio_h = win_h / content_h;
		if (ratio_h < ratio_w)
			ratio_w = ratio_h;
		l = (win_w / 2) - ((content_w * ratio_w) / 2);
		r = (win_w / 2) + ((content_w * ratio_w) / 2);
		t = (win_h / 2) - ((content_h * ratio_w) / 2);
		b = (win_h / 2) + ((content_h * ratio_w) / 2);
		break;
		case FULLSCR_SCALE_FULL:
		default:
		l = 0;
		t = 0;
		r = win_w;
		b = win_h;
		break;
	}

	dst->x = (int)l;
	dst->y = (int)t;
	dst->w = (int)(r - l);
	dst->h = (int)(b - t);
}

/*Render display texture to video window.*/
void video_renderer_present(int src_x, int src_y, int src_w, int src_h, int dblscan)
{
	@autoreleasepool {
		LOG_VIDEO_FRAMES("video_renderer_present: %d,%d + %d,%d\n", src_x, src_y, src_w, src_h);

		if (!metal_layer || !metal_pipeline_state || !metal_texture)
			return;

		CGFloat scale = cached_backing_scale;
		int win_w = cached_view_w;
		int win_h = cached_view_h;
		if (win_w <= 0 || win_h <= 0)
			return;

		/*Compute destination rect, applying fullscreen scaling if needed.*/
		metal_rect_t dest_rect;
		dest_rect.x = 0;
		dest_rect.y = 0;
		dest_rect.w = win_w;
		dest_rect.h = win_h;

		if (fullscreen)
		{
			if (dblscan)
				metal_scale(video_fullscreen_scale, win_w, win_h, &dest_rect, src_w, src_h * 2);
			else
				metal_scale(video_fullscreen_scale, win_w, win_h, &dest_rect, src_w, src_h);
		}

		id<CAMetalDrawable> drawable = [metal_layer nextDrawable];
		if (!drawable)
			return;

		/*Source rect in normalized texture coordinates.*/
		float sourceRect[4] = {
			(float)src_x / (float)TEXTURE_SIZE,
			(float)src_y / (float)TEXTURE_SIZE,
			(float)(src_x + src_w) / (float)TEXTURE_SIZE,
			(float)(src_y + src_h) / (float)TEXTURE_SIZE
		};

		MTLRenderPassDescriptor *passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
		passDesc.colorAttachments[0].texture = drawable.texture;
		passDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
		passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
		passDesc.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);

		id<MTLCommandBuffer> commandBuffer = [metal_command_queue commandBuffer];
		id<MTLRenderCommandEncoder> encoder =
			[commandBuffer renderCommandEncoderWithDescriptor:passDesc];

		/*Set viewport to the destination rect, scaled for Retina.*/
		MTLViewport viewport;
		viewport.originX = dest_rect.x * scale;
		viewport.originY = dest_rect.y * scale;
		viewport.width = dest_rect.w * scale;
		viewport.height = dest_rect.h * scale;
		viewport.znear = 0.0;
		viewport.zfar = 1.0;
		[encoder setViewport:viewport];

		[encoder setRenderPipelineState:metal_pipeline_state];
		[encoder setFragmentTexture:metal_texture atIndex:0];
		[encoder setFragmentSamplerState:(video_linear_filtering ? metal_sampler_linear : metal_sampler_nearest)
					 atIndex:0];
		[encoder setFragmentBytes:sourceRect length:sizeof(sourceRect) atIndex:0];
		[encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
		[encoder endEncoding];

		[commandBuffer presentDrawable:drawable];
		[commandBuffer commit];
		[commandBuffer waitUntilScheduled];
	}
}

int video_renderer_available(int id)
{
	/*Only the "auto" renderer (Metal) is available on macOS.*/
	return (id == RENDERER_AUTO) ? 1 : 0;
}

char *video_renderer_get_name(int id)
{
	static char *metal_name = "metal";
	static char *auto_name = "auto";
	static char *d3d_name = "direct3d";
	static char *gl_name = "opengl";
	static char *sw_name = "software";

	switch (id)
	{
		case RENDERER_AUTO:     return metal_name;
		case RENDERER_DIRECT3D: return d3d_name;
		case RENDERER_OPENGL:   return gl_name;
		case RENDERER_SOFTWARE: return sw_name;
		default:                return auto_name;
	}
}

int video_renderer_get_id(char *name)
{
	if (!strcmp(name, "metal") || !strcmp(name, "auto"))
		return RENDERER_AUTO;

	return RENDERER_AUTO;
}
