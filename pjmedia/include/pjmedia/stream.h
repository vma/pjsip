/* $Id$ */
/* 
 * Copyright (C) 2003-2006 Benny Prijono <benny@prijono.org>
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
#ifndef __PJMEDIA_STREAM_H__
#define __PJMEDIA_STREAM_H__


/**
 * @file stream.h
 * @brief Media Stream.
 */

#include <pjmedia/sound.h>
#include <pjmedia/codec.h>
#include <pjmedia/endpoint.h>
#include <pjmedia/port.h>
#include <pjmedia/rtcp.h>
#include <pj/sock.h>

PJ_BEGIN_DECL


/**
 * @defgroup PJMED_STRM Media Stream
 * @ingroup PJMEDIA
 * @{
 *
 * A media stream is a bidirectional multimedia communication between two
 * endpoints. It corresponds to a media description (m= line) in SDP.
 *
 * A media stream consists of two unidirectional channels:
 *  - encoding channel, which transmits unidirectional media to remote, and
 *  - decoding channel, which receives unidirectional media from remote.
 *
 * Application normally does not need to create the stream directly; it 
 * creates media session instead. The media session will create the media
 * streams as necessary, according to the media descriptors that present
 * in local and remote SDP.
 */

/**
 * Opaque declaration for media channel.
 * Media channel is unidirectional flow of media from sender to
 * receiver.
 */
typedef struct pjmedia_channel pjmedia_channel;

/** 
 * This structure describes media stream information. Each media stream
 * corresponds to one "m=" line in SDP session descriptor, and it has
 * its own RTP/RTCP socket pair.
 */
struct pjmedia_stream_info
{
    pjmedia_type	type;	    /**< Media type (audio, video)	    */
    pjmedia_dir		dir;	    /**< Media direction.		    */
    pj_sockaddr_in	rem_addr;   /**< Remote RTP address		    */
    pjmedia_codec_info	fmt;	    /**< Incoming codec format info.	    */
    pjmedia_codec_param *param;	    /**< Optional codec param.		    */
    unsigned		tx_pt;	    /**< Outgoing codec paylaod type.	    */
    int		        tx_event_pt;/**< Outgoing pt for telephone-events.  */
    int			rx_event_pt;/**< Incoming pt for telephone-events.  */
    pj_uint32_t		ssrc;	    /**< RTP SSRC.			    */
    int			jb_init;    /**< Jitter buffer init delay in msec.  
					 (-1 for default).		    */
    int			jb_min_pre; /**< Jitter buffer minimum prefetch
					 delay in msec (-1 for default).    */
    int			jb_max_pre; /**< Jitter buffer maximum prefetch
					 delay in msec (-1 for default).    */
    int			jb_max;	    /**< Jitter buffer max delay in msec.   */
};


/**
 * @see pjmedia_stream_info.
 */
typedef struct pjmedia_stream_info pjmedia_stream_info;


/**
 * Opaque declaration for media stream.
 */
typedef struct pjmedia_stream pjmedia_stream;


/**
 * @see pjmedia_transport_op.
 */
typedef struct pjmedia_transport pjmedia_transport;


/**
 * This structure describes the operations for the stream transport.
 */
struct pjmedia_transport_op
{
    /**
     * This function is called by the stream when the transport is about
     * to be used by the stream for the first time, and it tells the transport
     * about remote RTP address to send the packet and some callbacks to be 
     * called for incoming packets.
     */
    pj_status_t (*attach)(pjmedia_transport *tp,
			  pjmedia_stream *strm,
			  const pj_sockaddr_t *rem_addr,
			  unsigned addr_len,
			  void (*rtp_cb)(pjmedia_stream*,
					 const void*,
					 pj_ssize_t),
			  void (*rtcp_cb)(pjmedia_stream*,
					  const void*,
					  pj_ssize_t));

    /**
     * This function is called by the stream when the stream is no longer
     * need the transport (normally when the stream is about to be closed).
     */
    void (*detach)(pjmedia_transport *tp,
		   pjmedia_stream *strm);

    /**
     * This function is called by the stream to send RTP packet using the 
     * transport.
     */
    pj_status_t (*send_rtp)(pjmedia_transport *tp,
			    const void *pkt,
			    pj_size_t size);

    /**
     * This function is called by the stream to send RTCP packet using the
     * transport.
     */
    pj_status_t (*send_rtcp)(pjmedia_transport *tp,
			     const void *pkt,
			     pj_size_t size);

};


/**
 * @see pjmedia_transport_op.
 */
typedef struct pjmedia_transport_op pjmedia_transport_op;


/**
 * This structure declares stream transport. A stream transport is called
 * by the stream to transmit a packet, and will notify stream when
 * incoming packet is arrived.
 */
struct pjmedia_transport
{
    char		  name[PJ_MAX_OBJ_NAME];

    pjmedia_transport_op *op;
};



/**
 * Create a media stream based on the specified parameter. After the stream
 * has been created, application normally would want to get the media port 
 * interface of the streams, by calling pjmedia_stream_get_port(). The 
 * media port interface exports put_frame() and get_frame() function, used
 * to transmit and receive media frames from the stream.
 *
 * Without application calling put_frame() and get_frame(), there will be 
 * no media frames transmitted or received by the stream.
 *
 * @param endpt		Media endpoint.
 * @param pool		Pool to allocate memory for the stream. A large
 *			number of memory may be needed because jitter
 *			buffer needs to preallocate some storage.
 * @param info		Stream information.
 * @param tp		Stream transport instance used to transmit 
 *			and receive RTP/RTCP packets to/from the underlying 
 *			transport. 
 * @param user_data	Arbitrary user data (for future callback feature).
 * @param p_stream	Pointer to receive the media stream.
 *
 * @return		PJ_SUCCESS on success.
 */
PJ_DECL(pj_status_t) pjmedia_stream_create(pjmedia_endpt *endpt,
					   pj_pool_t *pool,
					   const pjmedia_stream_info *info,
					   pjmedia_transport *tp,
					   void *user_data,
					   pjmedia_stream **p_stream);

/**
 * Destroy the media stream.
 *
 * @param stream	The media stream.
 *
 * @return		PJ_SUCCESS on success.
 */
PJ_DECL(pj_status_t) pjmedia_stream_destroy(pjmedia_stream *stream);


/**
 * Get the media port interface of the stream. The media port interface
 * declares put_frame() and get_frame() function, which is the only 
 * way for application to transmit and receive media frames from the
 * stream.
 *
 * @param stream	The media stream.
 * @param p_port	Pointer to receive the port interface.
 *
 * @return		PJ_SUCCESS on success.
 */
PJ_DECL(pj_status_t) pjmedia_stream_get_port(pjmedia_stream *stream,
					     pjmedia_port **p_port );


/**
 * Get the media transport object associated with this stream.
 *
 * @param st		The media stream.
 *
 * @return		The transport object being used by the stream.
 */
PJ_DECL(pjmedia_transport*) pjmedia_stream_get_transport(pjmedia_stream *st);


/**
 * Start the media stream. This will start the appropriate channels
 * in the media stream, depending on the media direction that was set
 * when the stream was created.
 *
 * @param stream	The media stream.
 *
 * @return		PJ_SUCCESS on success.
 */
PJ_DECL(pj_status_t) pjmedia_stream_start(pjmedia_stream *stream);


/**
 * Get the stream statistics.
 *
 * @param stream	The media stream.
 * @param stat		Media stream statistics.
 *
 * @return		PJ_SUCCESS on success.
 */
PJ_DECL(pj_status_t) pjmedia_stream_get_stat( const pjmedia_stream *stream,
					      pjmedia_rtcp_stat *stat);

/**
 * Pause the individual channel in the stream.
 *
 * @param stream	The media channel.
 * @param dir		Which direction to pause.
 *
 * @return		PJ_SUCCESS on success.
 */
PJ_DECL(pj_status_t) pjmedia_stream_pause( pjmedia_stream *stream,
					   pjmedia_dir dir);

/**
 * Resume the individual channel in the stream.
 *
 * @param stream	The media channel.
 * @param dir		Which direction to resume.
 *
 * @return		PJ_SUCCESS on success;
 */
PJ_DECL(pj_status_t) pjmedia_stream_resume(pjmedia_stream *stream,
					   pjmedia_dir dir);

/**
 * Transmit DTMF to this stream. The DTMF will be transmitted uisng
 * RTP telephone-events as described in RFC 2833. This operation is
 * only valid for audio stream.
 *
 * @param stream	The media stream.
 * @param ascii_digit	String containing digits to be sent to remote.
 *			Currently the maximum number of digits are 32.
 *
 * @return		PJ_SUCCESS on success.
 */
PJ_DECL(pj_status_t) pjmedia_stream_dial_dtmf(pjmedia_stream *stream,
					      const pj_str_t *ascii_digit);


/**
 * Check if the stream has incoming DTMF digits in the incoming DTMF
 * queue. Incoming DTMF digits received via RFC 2833 mechanism are
 * saved in the incoming digits queue.
 *
 * @param stream	The media stream.
 *
 * @return		Non-zero (PJ_TRUE) if the stream has received DTMF
 *			digits in the .
 */
PJ_DECL(pj_bool_t) pjmedia_stream_check_dtmf(pjmedia_stream *stream);


/**
 * Retrieve the incoming DTMF digits from the stream, and remove the digits
 * from stream's DTMF buffer. Note that the digits buffer will not be NULL 
 * terminated.
 *
 * @param stream	The media stream.
 * @param ascii_digits	Buffer to receive the digits. The length of this
 *			buffer is indicated in the "size" argument.
 * @param size		On input, contains the maximum digits to be copied
 *			to the buffer.
 *			On output, it contains the actual digits that has
 *			been copied to the buffer.
 *
 * @return		Non-zero (PJ_TRUE) if the stream has received DTMF
 *			digits in the .
 */
PJ_DECL(pj_status_t) pjmedia_stream_get_dtmf( pjmedia_stream *stream,
					      char *ascii_digits,
					      unsigned *size);


/**
 * @}
 */

PJ_END_DECL


#endif	/* __PJMEDIA_STREAM_H__ */
