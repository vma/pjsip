/* $Id$ */
/*
 * Copyright (C) 2008-2011 Teluu Inc. (http://www.teluu.com)
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */
#include <pjmedia-videodev/videodev_imp.h>
#include <pj/assert.h>
#include <pj/log.h>
#include <pj/os.h>

#if defined(PJMEDIA_HAS_VIDEO) && PJMEDIA_HAS_VIDEO != 0 && \
    defined(PJMEDIA_VIDEO_DEV_HAS_IOS) && PJMEDIA_VIDEO_DEV_HAS_IOS != 0

#include "Availability.h"
#ifdef __IPHONE_4_0

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

#define THIS_FILE		"ios_dev.c"
#define DEFAULT_CLOCK_RATE	90000
#define DEFAULT_WIDTH		352
#define DEFAULT_HEIGHT		288
#define DEFAULT_FPS		15

typedef struct ios_fmt_info
{
    pjmedia_format_id   pjmedia_format;
    UInt32		ios_format;
} ios_fmt_info;

static ios_fmt_info ios_fmts[] =
{
    { PJMEDIA_FORMAT_BGRA, kCVPixelFormatType_32BGRA }
};

/* qt device info */
struct ios_dev_info
{
    pjmedia_vid_dev_info	 info;
    AVCaptureDevice             *dev;
};

/* qt factory */
struct ios_factory
{
    pjmedia_vid_dev_factory	 base;
    pj_pool_t			*pool;
    pj_pool_factory		*pf;

    unsigned			 dev_count;
    struct ios_dev_info		*dev_info;
};

@interface VOutDelegate: NSObject 
			 <AVCaptureVideoDataOutputSampleBufferDelegate>
{
@public
    struct ios_stream *stream;
}
@end

/* Video stream. */
struct ios_stream
{
    pjmedia_vid_dev_stream  base;		/**< Base stream       */
    pjmedia_vid_dev_param   param;		/**< Settings	       */
    pj_pool_t		   *pool;		/**< Memory pool       */
    struct ios_factory     *factory;            /**< Factory           */

    pjmedia_vid_dev_cb	    vid_cb;		/**< Stream callback   */
    void		   *user_data;          /**< Application data  */

    pjmedia_rect_size	    size;
    pj_uint8_t		    bpp;
    unsigned		    bytes_per_row;
    unsigned		    frame_size;
    
    AVCaptureSession		*cap_session;
    AVCaptureDeviceInput	*dev_input;
    AVCaptureVideoDataOutput	*video_output;
    VOutDelegate		*vout_delegate;
    
    void		*render_buf;
    pj_size_t		 render_buf_size;
    CGDataProviderRef    render_data_provider;
    UIView              *render_view;
    
    pj_timestamp	 frame_ts;
    unsigned		 ts_inc;

    pj_bool_t		 thread_initialized;
    pj_thread_desc	 thread_desc;
    pj_thread_t		*thread;
};


/* Prototypes */
static pj_status_t ios_factory_init(pjmedia_vid_dev_factory *f);
static pj_status_t ios_factory_destroy(pjmedia_vid_dev_factory *f);
static pj_status_t ios_factory_refresh(pjmedia_vid_dev_factory *f);
static unsigned    ios_factory_get_dev_count(pjmedia_vid_dev_factory *f);
static pj_status_t ios_factory_get_dev_info(pjmedia_vid_dev_factory *f,
					    unsigned index,
					    pjmedia_vid_dev_info *info);
static pj_status_t ios_factory_default_param(pj_pool_t *pool,
					     pjmedia_vid_dev_factory *f,
					     unsigned index,
					     pjmedia_vid_dev_param *param);
static pj_status_t ios_factory_create_stream(
					pjmedia_vid_dev_factory *f,
					pjmedia_vid_dev_param *param,
					const pjmedia_vid_dev_cb *cb,
					void *user_data,
					pjmedia_vid_dev_stream **p_vid_strm);

static pj_status_t ios_stream_get_param(pjmedia_vid_dev_stream *strm,
				        pjmedia_vid_dev_param *param);
static pj_status_t ios_stream_get_cap(pjmedia_vid_dev_stream *strm,
				      pjmedia_vid_dev_cap cap,
				      void *value);
static pj_status_t ios_stream_set_cap(pjmedia_vid_dev_stream *strm,
				      pjmedia_vid_dev_cap cap,
				      const void *value);
static pj_status_t ios_stream_start(pjmedia_vid_dev_stream *strm);
static pj_status_t ios_stream_put_frame(pjmedia_vid_dev_stream *strm,
					const pjmedia_frame *frame);
static pj_status_t ios_stream_stop(pjmedia_vid_dev_stream *strm);
static pj_status_t ios_stream_destroy(pjmedia_vid_dev_stream *strm);

/* Operations */
static pjmedia_vid_dev_factory_op factory_op =
{
    &ios_factory_init,
    &ios_factory_destroy,
    &ios_factory_get_dev_count,
    &ios_factory_get_dev_info,
    &ios_factory_default_param,
    &ios_factory_create_stream,
    &ios_factory_refresh
};

static pjmedia_vid_dev_stream_op stream_op =
{
    &ios_stream_get_param,
    &ios_stream_get_cap,
    &ios_stream_set_cap,
    &ios_stream_start,
    NULL,
    &ios_stream_put_frame,
    &ios_stream_stop,
    &ios_stream_destroy
};


/****************************************************************************
 * Factory operations
 */
/*
 * Init ios_ video driver.
 */
pjmedia_vid_dev_factory* pjmedia_ios_factory(pj_pool_factory *pf)
{
    struct ios_factory *f;
    pj_pool_t *pool;

    pool = pj_pool_create(pf, "ios video", 512, 512, NULL);
    f = PJ_POOL_ZALLOC_T(pool, struct ios_factory);
    f->pf = pf;
    f->pool = pool;
    f->base.op = &factory_op;

    return &f->base;
}


/* API: init factory */
static pj_status_t ios_factory_init(pjmedia_vid_dev_factory *f)
{
    struct ios_factory *qf = (struct ios_factory*)f;
    struct ios_dev_info *qdi;
    unsigned i, l, first_idx, front_idx = -1;
    enum { MAX_DEV_COUNT = 8 };
    
    /* Initialize input and output devices here */
    qf->dev_info = (struct ios_dev_info*)
		   pj_pool_calloc(qf->pool, MAX_DEV_COUNT,
				  sizeof(struct ios_dev_info));
    qf->dev_count = 0;
    
    /* Init output device */
    qdi = &qf->dev_info[qf->dev_count++];
    pj_bzero(qdi, sizeof(*qdi));
    pj_ansi_strncpy(qdi->info.name, "UIView", sizeof(qdi->info.name));
    pj_ansi_strncpy(qdi->info.driver, "iOS", sizeof(qdi->info.driver));
    qdi->info.dir = PJMEDIA_DIR_RENDER;
    qdi->info.has_callback = PJ_FALSE;
    qdi->info.caps = PJMEDIA_VID_DEV_CAP_OUTPUT_WINDOW;
    
    /* Init input device */
    first_idx = qf->dev_count;
    if (NSClassFromString(@"AVCaptureSession")) {
        for (AVCaptureDevice *device in [AVCaptureDevice devices]) {
            if (![device hasMediaType:AVMediaTypeVideo] ||
                qf->dev_count >= MAX_DEV_COUNT)
            {
                continue;
            }

            if (front_idx == -1 &&
                [device position] == AVCaptureDevicePositionFront)
            {
                front_idx = qf->dev_count;
            }

            qdi = &qf->dev_info[qf->dev_count++];
            pj_bzero(qdi, sizeof(*qdi));
            pj_ansi_strncpy(qdi->info.name, [[device localizedName] UTF8String],
                            sizeof(qdi->info.name));
            pj_ansi_strncpy(qdi->info.driver, "iOS", sizeof(qdi->info.driver));
            qdi->info.dir = PJMEDIA_DIR_CAPTURE;
            qdi->info.has_callback = PJ_TRUE;
            qdi->info.caps = PJMEDIA_VID_DEV_CAP_INPUT_PREVIEW |
		    	     PJMEDIA_VID_DEV_CAP_SWITCH |
                             PJMEDIA_VID_DEV_CAP_OUTPUT_WINDOW;
            qdi->dev = device;
        }
    }
    
    /* Set front camera to be the first input device (as default dev) */
    if (front_idx != -1 && front_idx != first_idx) {
        struct ios_dev_info tmp_dev_info = qf->dev_info[first_idx];
        qf->dev_info[first_idx] = qf->dev_info[front_idx];
        qf->dev_info[front_idx] = tmp_dev_info;
    }

    /* Set supported formats */
    for (i = 0; i < qf->dev_count; i++) {
	qdi = &qf->dev_info[i];
	qdi->info.fmt_cnt = PJ_ARRAY_SIZE(ios_fmts);	    
	qdi->info.caps |= PJMEDIA_VID_DEV_CAP_FORMAT;
	
	for (l = 0; l < PJ_ARRAY_SIZE(ios_fmts); l++) {
	    pjmedia_format *fmt = &qdi->info.fmt[l];
	    pjmedia_format_init_video(fmt,
				      ios_fmts[l].pjmedia_format,
				      DEFAULT_WIDTH,
				      DEFAULT_HEIGHT,
				      DEFAULT_FPS, 1);	
	}
    }
    
    PJ_LOG(4, (THIS_FILE, "iOS video initialized with %d devices:",
	       qf->dev_count));
    for (i = 0; i < qf->dev_count; i++) {
        qdi = &qf->dev_info[i];
        PJ_LOG(4, (THIS_FILE, "%2d: [%s] %s - %s", i,
                   (qdi->info.dir==PJMEDIA_DIR_CAPTURE? "Capturer":"Renderer"),
                   qdi->info.driver, qdi->info.name));
    }

    return PJ_SUCCESS;
}

/* API: destroy factory */
static pj_status_t ios_factory_destroy(pjmedia_vid_dev_factory *f)
{
    struct ios_factory *qf = (struct ios_factory*)f;
    pj_pool_t *pool = qf->pool;

    qf->pool = NULL;
    pj_pool_release(pool);

    return PJ_SUCCESS;
}

/* API: refresh the list of devices */
static pj_status_t ios_factory_refresh(pjmedia_vid_dev_factory *f)
{
    PJ_UNUSED_ARG(f);
    return PJ_SUCCESS;
}

/* API: get number of devices */
static unsigned ios_factory_get_dev_count(pjmedia_vid_dev_factory *f)
{
    struct ios_factory *qf = (struct ios_factory*)f;
    return qf->dev_count;
}

/* API: get device info */
static pj_status_t ios_factory_get_dev_info(pjmedia_vid_dev_factory *f,
					    unsigned index,
					    pjmedia_vid_dev_info *info)
{
    struct ios_factory *qf = (struct ios_factory*)f;

    PJ_ASSERT_RETURN(index < qf->dev_count, PJMEDIA_EVID_INVDEV);

    pj_memcpy(info, &qf->dev_info[index].info, sizeof(*info));

    return PJ_SUCCESS;
}

/* API: create default device parameter */
static pj_status_t ios_factory_default_param(pj_pool_t *pool,
					     pjmedia_vid_dev_factory *f,
					     unsigned index,
					     pjmedia_vid_dev_param *param)
{
    struct ios_factory *qf = (struct ios_factory*)f;
    struct ios_dev_info *di;

    PJ_ASSERT_RETURN(index < qf->dev_count, PJMEDIA_EVID_INVDEV);
    PJ_UNUSED_ARG(pool);
    
    di = &qf->dev_info[index];

    pj_bzero(param, sizeof(*param));
    if (di->info.dir & PJMEDIA_DIR_CAPTURE) {
	param->dir = PJMEDIA_DIR_CAPTURE;
	param->cap_id = index;
	param->rend_id = PJMEDIA_VID_INVALID_DEV;
    } else if (di->info.dir & PJMEDIA_DIR_RENDER) {
	param->dir = PJMEDIA_DIR_RENDER;
	param->rend_id = index;
	param->cap_id = PJMEDIA_VID_INVALID_DEV;
    } else {
	return PJMEDIA_EVID_INVDEV;
    }
    
    param->flags = PJMEDIA_VID_DEV_CAP_FORMAT;
    param->clock_rate = DEFAULT_CLOCK_RATE;
    pj_memcpy(&param->fmt, &di->info.fmt[0], sizeof(param->fmt));

    return PJ_SUCCESS;
}

@implementation VOutDelegate
- (void)update_image
{    
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGImageRef cgIm = CGImageCreate(stream->size.w, stream->size.h,
                                    8, 32, stream->bytes_per_row, colorSpace,
                                    kCGImageAlphaFirst |
                                    kCGBitmapByteOrder32Little,
                                    stream->render_data_provider, 0,
                                    false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(colorSpace);
    
    stream->render_view.layer.contents = (__bridge id)(cgIm);
    CGImageRelease(cgIm);

    [pool release];
}    

- (void)captureOutput:(AVCaptureOutput *)captureOutput 
		      didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
		      fromConnection:(AVCaptureConnection *)connection
{
    pjmedia_frame frame;
    CVImageBufferRef imageBuffer;

    if (!sampleBuffer)
	return;
    
    /* Get a CMSampleBuffer's Core Video image buffer for the media data */
    imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer); 
    
    /* Lock the base address of the pixel buffer */
    CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
    
    frame.type = PJMEDIA_FRAME_TYPE_VIDEO;
    frame.buf = CVPixelBufferGetBaseAddress(imageBuffer);
    frame.size = stream->frame_size;
    frame.bit_info = 0;
    frame.timestamp.u64 = stream->frame_ts.u64;
    
    if (stream->vid_cb.capture_cb) {
        if (stream->thread_initialized == 0 || !pj_thread_is_registered())
        {
            pj_bzero(stream->thread_desc, sizeof(pj_thread_desc));
            pj_thread_register("ios_vdev", stream->thread_desc,
                               &stream->thread);
            stream->thread_initialized = 1;
        }

        (*stream->vid_cb.capture_cb)(&stream->base, stream->user_data, &frame);
    }

    stream->frame_ts.u64 += stream->ts_inc;
    
    /* Unlock the pixel buffer */
    CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
}
@end

static ios_fmt_info* get_ios_format_info(pjmedia_format_id id)
{
    unsigned i;
    
    for (i = 0; i < PJ_ARRAY_SIZE(ios_fmts); i++) {
        if (ios_fmts[i].pjmedia_format == id)
            return &ios_fmts[i];
    }
    
    return NULL;
}


static pj_status_t ios_init_view(struct ios_stream *strm)
{
    pjmedia_vid_dev_param *param = &strm->param;
    CGRect view_rect = CGRectMake(0, 0, param->fmt.det.vid.size.w,
                                  param->fmt.det.vid.size.h);
    
    if (param->flags & PJMEDIA_VID_DEV_CAP_OUTPUT_RESIZE) {
	view_rect.size.width = param->disp_size.w;
        view_rect.size.height = param->disp_size.h;
    }
    
    if (param->flags & PJMEDIA_VID_DEV_CAP_OUTPUT_POSITION) {
        view_rect.origin.x = param->window_pos.x;
        view_rect.origin.y = param->window_pos.y;
    }
    
    strm->render_view = [[UIView alloc] initWithFrame:view_rect];
    strm->param.window.info.ios.window = strm->render_view;
    
    if (param->flags & PJMEDIA_VID_DEV_CAP_OUTPUT_WINDOW) {
        PJ_ASSERT_RETURN(param->window.info.ios.window, PJ_EINVAL);
        ios_stream_set_cap(&strm->base, PJMEDIA_VID_DEV_CAP_OUTPUT_WINDOW,
                           param->window.info.ios.window);
    }
    if (param->flags & PJMEDIA_VID_DEV_CAP_OUTPUT_HIDE) {
        ios_stream_set_cap(&strm->base, PJMEDIA_VID_DEV_CAP_OUTPUT_HIDE,
                           &param->window_hide);
    }
    if (param->flags & PJMEDIA_VID_DEV_CAP_ORIENTATION) {
        ios_stream_set_cap(&strm->base, PJMEDIA_VID_DEV_CAP_ORIENTATION,
                           &param->orient);
    }

    return PJ_SUCCESS;
}


/* API: create stream */
static pj_status_t ios_factory_create_stream(
					pjmedia_vid_dev_factory *f,
					pjmedia_vid_dev_param *param,
					const pjmedia_vid_dev_cb *cb,
					void *user_data,
					pjmedia_vid_dev_stream **p_vid_strm)
{
    struct ios_factory *qf = (struct ios_factory*)f;
    pj_pool_t *pool;
    struct ios_stream *strm;
    pjmedia_video_format_detail *vfd;
    const pjmedia_video_format_info *vfi;
    pj_status_t status = PJ_SUCCESS;
    ios_fmt_info *ifi = get_ios_format_info(param->fmt.id);

    PJ_ASSERT_RETURN(f && param && p_vid_strm, PJ_EINVAL);
    PJ_ASSERT_RETURN(param->fmt.type == PJMEDIA_TYPE_VIDEO &&
		     param->fmt.detail_type == PJMEDIA_FORMAT_DETAIL_VIDEO &&
                     (param->dir == PJMEDIA_DIR_CAPTURE ||
                     param->dir == PJMEDIA_DIR_RENDER),
		     PJ_EINVAL);

    if (!(ifi = get_ios_format_info(param->fmt.id)))
        return PJMEDIA_EVID_BADFORMAT;
    
    vfi = pjmedia_get_video_format_info(NULL, param->fmt.id);
    if (!vfi)
        return PJMEDIA_EVID_BADFORMAT;

    /* Create and Initialize stream descriptor */
    pool = pj_pool_create(qf->pf, "ios-dev", 4000, 4000, NULL);
    PJ_ASSERT_RETURN(pool != NULL, PJ_ENOMEM);

    strm = PJ_POOL_ZALLOC_T(pool, struct ios_stream);
    pj_memcpy(&strm->param, param, sizeof(*param));
    strm->pool = pool;
    pj_memcpy(&strm->vid_cb, cb, sizeof(*cb));
    strm->user_data = user_data;
    strm->factory = qf;
    
    vfd = pjmedia_format_get_video_format_detail(&strm->param.fmt, PJ_TRUE);
    pj_memcpy(&strm->size, &vfd->size, sizeof(vfd->size));
    strm->bpp = vfi->bpp;
    strm->bytes_per_row = strm->size.w * strm->bpp / 8;
    strm->frame_size = strm->bytes_per_row * strm->size.h;
    strm->ts_inc = PJMEDIA_SPF2(param->clock_rate, &vfd->fps, 1);

    if (param->dir & PJMEDIA_DIR_CAPTURE) {
        /* Create capture stream here */
	strm->cap_session = [[AVCaptureSession alloc] init];
	if (!strm->cap_session) {
	    status = PJ_ENOMEM;
	    goto on_error;
	}
        
	/* Just hardcode to always capture 352x288 for now */
        strm->cap_session.sessionPreset = AVCaptureSessionPreset352x288;
        vfd->size.w = 352;
        vfd->size.h = 288;
        strm->size = vfd->size;
        strm->bytes_per_row = strm->size.w * strm->bpp / 8;
        strm->frame_size = strm->bytes_per_row * strm->size.h;
        
        /* Update param as output */
        param->fmt = strm->param.fmt;

        /* Set frame rate, this may only work on iOS 7 or later */
        AVCaptureDevice *dev = qf->dev_info[param->cap_id].dev;
        if ([dev respondsToSelector:@selector(activeVideoMinFrameDuration)] &&
            [dev lockForConfiguration:NULL])
        {
            dev.activeVideoMinFrameDuration = CMTimeMake(vfd->fps.denum,
                                                            vfd->fps.num);
            dev.activeVideoMaxFrameDuration = CMTimeMake(vfd->fps.denum,
                                                            vfd->fps.num);
            [dev unlockForConfiguration];
        }
        
	/* Add the video device to the session as a device input */
        NSError *error;
	strm->dev_input = [AVCaptureDeviceInput
			   deviceInputWithDevice:dev
			   error: &error];
	if (!strm->dev_input) {
	    status = PJMEDIA_EVID_SYSERR;
	    goto on_error;
	}
	[strm->cap_session addInput:strm->dev_input];
	
	strm->video_output = [[[AVCaptureVideoDataOutput alloc] init]
			      autorelease];
	if (!strm->video_output) {
	    status = PJMEDIA_EVID_SYSERR;
	    goto on_error;
	}
        
        strm->video_output.alwaysDiscardsLateVideoFrames = YES;
	[strm->cap_session addOutput:strm->video_output];
	
	/* Configure the video output */
	strm->vout_delegate = [VOutDelegate alloc];
	strm->vout_delegate->stream = strm;
	dispatch_queue_t queue = dispatch_queue_create("myQueue", NULL);
	[strm->video_output setSampleBufferDelegate:strm->vout_delegate
                                              queue:queue];
	dispatch_release(queue);
	
	strm->video_output.videoSettings =
	    [NSDictionary dictionaryWithObjectsAndKeys:
			  [NSNumber numberWithInt:ifi->ios_format],
			  kCVPixelBufferPixelFormatTypeKey, nil];
        
        /* Native preview */
        if ((param->flags & PJMEDIA_VID_DEV_CAP_INPUT_PREVIEW) &&
            param->native_preview)
        {
            /* Preview layer instantiation should be in main thread! */
            dispatch_async(dispatch_get_main_queue(), ^{
                /* Create view */
                ios_init_view(strm);

                /* Create preview layer */
                AVCaptureVideoPreviewLayer *previewLayer =
                    [AVCaptureVideoPreviewLayer layerWithSession: strm->cap_session];

                /* Attach preview layer to a UIView */
                CGRect r = strm->render_view.bounds;
                previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
                previewLayer.frame = r;
                [[strm->render_view layer] addSublayer:previewLayer];

                NSLog(@"Native preview initialized.");
            });
        }
        
    } else if (param->dir & PJMEDIA_DIR_RENDER) {

        /* Create renderer stream here */
        
        status = ios_init_view(strm);
        if (status != PJ_SUCCESS)
            goto on_error;
        
	if (!strm->vout_delegate) {
	    strm->vout_delegate = [VOutDelegate alloc];
	    strm->vout_delegate->stream = strm;
	}
        
	strm->render_buf = pj_pool_alloc(pool, strm->frame_size);
	strm->render_buf_size = strm->frame_size;
        strm->render_data_provider = CGDataProviderCreateWithData(NULL,
                                            strm->render_buf, strm->frame_size,
                                            NULL);
    }
    
    /* Done */
    strm->base.op = &stream_op;
    *p_vid_strm = &strm->base;
    
    return PJ_SUCCESS;
    
on_error:
    ios_stream_destroy((pjmedia_vid_dev_stream *)strm);
    
    return status;
}

/* API: Get stream info. */
static pj_status_t ios_stream_get_param(pjmedia_vid_dev_stream *s,
				        pjmedia_vid_dev_param *pi)
{
    struct ios_stream *strm = (struct ios_stream*)s;

    PJ_ASSERT_RETURN(strm && pi, PJ_EINVAL);

    pj_memcpy(pi, &strm->param, sizeof(*pi));

    return PJ_SUCCESS;
}

/* API: get capability */
static pj_status_t ios_stream_get_cap(pjmedia_vid_dev_stream *s,
				      pjmedia_vid_dev_cap cap,
				      void *pval)
{
    struct ios_stream *strm = (struct ios_stream*)s;
    
    PJ_ASSERT_RETURN(s && pval, PJ_EINVAL);

    switch (cap) {
        case PJMEDIA_VID_DEV_CAP_OUTPUT_WINDOW:
        {
            pjmedia_vid_dev_hwnd *hwnd = (pjmedia_vid_dev_hwnd*) pval;
            hwnd->type = PJMEDIA_VID_DEV_HWND_TYPE_NONE;
            hwnd->info.ios.window = (void*)strm->render_view;
            return PJ_SUCCESS;
        }
            
        default:
            break;
    }
    
    return PJMEDIA_EVID_INVCAP;
}

/* API: set capability */
static pj_status_t ios_stream_set_cap(pjmedia_vid_dev_stream *s,
				      pjmedia_vid_dev_cap cap,
				      const void *pval)
{
    struct ios_stream *strm = (struct ios_stream*)s;

    PJ_ASSERT_RETURN(s && pval, PJ_EINVAL);

    switch (cap) {
        /* Fast switch */
        case PJMEDIA_VID_DEV_CAP_SWITCH:
        {
            if (!strm->cap_session) return PJ_EINVAL;
            
            NSError *error;
            struct ios_dev_info* di = strm->factory->dev_info;
            pjmedia_vid_dev_switch_param *p =
                                    (pjmedia_vid_dev_switch_param*)pval;

            /* Verify target capture ID */
            if (p->target_id < 0 || p->target_id >= strm->factory->dev_count)
                return PJ_EINVAL;
            
            if (di[p->target_id].info.dir != PJMEDIA_DIR_CAPTURE ||
                !di[p->target_id].dev)
            {
                return PJ_EINVAL;
            }
            
            /* Just return if current and target device are the same */
            if (strm->param.cap_id == p->target_id)
                return PJ_SUCCESS;
            
            /* Ok, let's do the switch */
            AVCaptureDeviceInput *cur_dev_input = strm->dev_input;
                    //[AVCaptureDeviceInput
                    // deviceInputWithDevice:di[strm->param.cap_id].dev
                    // error:&error];
            AVCaptureDeviceInput *new_dev_input =
                    [AVCaptureDeviceInput
                     deviceInputWithDevice:di[p->target_id].dev
                     error:&error];

            [strm->cap_session beginConfiguration];
            [strm->cap_session removeInput:cur_dev_input];
            [strm->cap_session addInput:new_dev_input];
            [strm->cap_session commitConfiguration];
            
            strm->dev_input = new_dev_input;
            strm->param.cap_id = p->target_id;
            
            return PJ_SUCCESS;
        }
        
        case PJMEDIA_VID_DEV_CAP_FORMAT:
	{
            const pjmedia_video_format_info *vfi;
            pjmedia_video_format_detail *vfd;
            pjmedia_format *fmt = (pjmedia_format *)pval;
            ios_fmt_info *ifi;
        
            if (!(ifi = get_ios_format_info(fmt->id)))
                return PJMEDIA_EVID_BADFORMAT;
        
            vfi = pjmedia_get_video_format_info(pjmedia_video_format_mgr_instance(),
                                                fmt->id);
            if (!vfi)
                return PJMEDIA_EVID_BADFORMAT;
        
            pjmedia_format_copy(&strm->param.fmt, fmt);
        
            vfd = pjmedia_format_get_video_format_detail(fmt, PJ_TRUE);
	    pj_memcpy(&strm->size, &vfd->size, sizeof(vfd->size));
	    strm->bytes_per_row = strm->size.w * strm->bpp / 8;
	    strm->frame_size = strm->bytes_per_row * strm->size.h;
	    if (strm->render_buf_size < strm->frame_size) {
          	strm->render_buf = pj_pool_alloc(strm->pool, strm->frame_size);
	      	strm->render_buf_size = strm->frame_size;
		CGDataProviderRelease(strm->render_data_provider);
	        strm->render_data_provider = CGDataProviderCreateWithData(NULL,
	                                                strm->render_buf, strm->frame_size,
	                                                NULL);
	    }
	    
	    return PJ_SUCCESS;
	}
	
        case PJMEDIA_VID_DEV_CAP_OUTPUT_WINDOW:
        {
            UIView *view = (UIView *)pval;
            strm->param.window.info.ios.window = (void *)pval;
            dispatch_async(dispatch_get_main_queue(),
                           ^{[view addSubview:strm->render_view];});
            return PJ_SUCCESS;
        }
            
        case PJMEDIA_VID_DEV_CAP_OUTPUT_RESIZE:
        {
            pj_memcpy(&strm->param.disp_size, pval,
                      sizeof(strm->param.disp_size));
            CGRect r = strm->render_view.bounds;
            r.size = CGSizeMake(strm->param.disp_size.w,
                                strm->param.disp_size.h);
            dispatch_async(dispatch_get_main_queue(), ^{
		strm->render_view.bounds = r;
            });
            return PJ_SUCCESS;
        }
    
        case PJMEDIA_VID_DEV_CAP_OUTPUT_POSITION:
        {
            pj_memcpy(&strm->param.window_pos, pval,
                      sizeof(strm->param.window_pos));
            dispatch_async(dispatch_get_main_queue(), ^{
                strm->render_view.center =
                            CGPointMake(strm->param.window_pos.x +
                                        strm->param.disp_size.w/2.0,
                                        strm->param.window_pos.y +
                                        strm->param.disp_size.h/2.0);
            });
            return PJ_SUCCESS;
        }
            
        case PJMEDIA_VID_DEV_CAP_OUTPUT_HIDE:
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                strm->render_view.hidden = (BOOL)(*((pj_bool_t *)pval));
            });
            return PJ_SUCCESS;
        }
            
        /* TODO: orientation for capture device */
        case PJMEDIA_VID_DEV_CAP_ORIENTATION:
        {
            pj_memcpy(&strm->param.orient, pval,
                      sizeof(strm->param.orient));
            if (strm->param.orient == PJMEDIA_ORIENT_UNKNOWN)
                return PJ_SUCCESS;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                strm->render_view.transform =
                    CGAffineTransformMakeRotation(
                        ((int)strm->param.orient-1) * -M_PI_2);
            });
            return PJ_SUCCESS;
        }
        
        default:
            break;
    }

    return PJMEDIA_EVID_INVCAP;
}

/* API: Start stream. */
static pj_status_t ios_stream_start(pjmedia_vid_dev_stream *strm)
{
    struct ios_stream *stream = (struct ios_stream*)strm;

    PJ_UNUSED_ARG(stream);

    PJ_LOG(4, (THIS_FILE, "Starting iOS video stream"));

    if (stream->cap_session) {
	[stream->cap_session startRunning];
    
	if (![stream->cap_session isRunning])
	    return PJ_EUNKNOWN;
    }
    
    return PJ_SUCCESS;
}


/* API: Put frame from stream */
static pj_status_t ios_stream_put_frame(pjmedia_vid_dev_stream *strm,
					const pjmedia_frame *frame)
{
    struct ios_stream *stream = (struct ios_stream*)strm;
    //NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    if (stream->frame_size >= frame->size)
        pj_memcpy(stream->render_buf, frame->buf, frame->size);
    else
        pj_memcpy(stream->render_buf, frame->buf, stream->frame_size);
    
    /* Perform video display in a background thread */
    dispatch_async(dispatch_get_main_queue(),
                   ^{[stream->vout_delegate update_image];});

    //[pool release];
    
    return PJ_SUCCESS;
}

/* API: Stop stream. */
static pj_status_t ios_stream_stop(pjmedia_vid_dev_stream *strm)
{
    struct ios_stream *stream = (struct ios_stream*)strm;

    PJ_UNUSED_ARG(stream);

    PJ_LOG(4, (THIS_FILE, "Stopping iOS video stream"));

    if (stream->cap_session && [stream->cap_session isRunning])
	[stream->cap_session stopRunning];
    
    return PJ_SUCCESS;
}


/* API: Destroy stream. */
static pj_status_t ios_stream_destroy(pjmedia_vid_dev_stream *strm)
{
    struct ios_stream *stream = (struct ios_stream*)strm;

    PJ_ASSERT_RETURN(stream != NULL, PJ_EINVAL);

    ios_stream_stop(strm);
    
    if (stream->cap_session) {
        [stream->cap_session removeInput:stream->dev_input];
        [stream->cap_session removeOutput:stream->video_output];
	[stream->cap_session release];
	stream->cap_session = nil;
    }    
    if (stream->dev_input) {
        stream->dev_input = nil;
    }
 
    if (stream->vout_delegate) {
	[stream->vout_delegate release];
	stream->vout_delegate = nil;
    }
    if (stream->video_output) {
        stream->video_output = nil;
    }

    if (stream->render_view) {
        dispatch_async(dispatch_get_main_queue(),
          ^{
              [stream->render_view removeFromSuperview];
              [stream->render_view release];
           });
        stream->render_view = NULL;
    }
    
    if (stream->render_data_provider) {
        CGDataProviderRelease(stream->render_data_provider);
        stream->render_data_provider = NULL;
    }

    pj_pool_release(stream->pool);

    return PJ_SUCCESS;
}

#endif  /* __IPHONE_4_0 */
#endif	/* PJMEDIA_VIDEO_DEV_HAS_IOS */
