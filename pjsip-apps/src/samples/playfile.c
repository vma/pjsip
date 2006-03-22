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

#include <pjmedia.h>

/*
 * playfile.c
 *
 * PURPOSE:
 *  Play a WAV file to sound player device.
 *
 * USAGE:
 *  playfile FILE.WAV
 *
 *  The WAV file could have mono or stereo channels with arbitrary
 *  sampling rate, but MUST contain uncompressed (i.e. 16bit) PCM.
 *
 */

#include <pjmedia.h>
#include <pjlib.h>

#include <stdio.h>

/* For logging purpose. */
#define THIS_FILE   "playfile.c"


/* Util to display the error message for the specified error code  */
static int app_perror( const char *sender, const char *title, 
		       pj_status_t status)
{
    char errmsg[PJ_ERR_MSG_SIZE];

    pj_strerror(status, errmsg, sizeof(errmsg));

    printf("%s: %s [code=%d]\n", title, errmsg, status);
    return 1;
}


/*
 * main()
 */
int main(int argc, char *argv[])
{
    pj_caching_pool cp;
    pjmedia_endpt *med_endpt;
    pj_pool_t *pool;
    pjmedia_port *file_port;
    pjmedia_snd_port *snd_port;
    char tmp[10];
    pj_status_t status;


    /* Verify cmd line arguments. */
    if (argc != 2) {
	puts("");
	puts("Usage: ");
	puts("  playfile <wav-file>");
	puts("");
	puts("The WAV file could have mono or stereo channels with arbitrary");
	puts("sampling rate, but MUST contain uncompressed (i.e. 16bit) PCM.");
	return 0;
    }

    /* Must init PJLIB first: */
    status = pj_init();
    PJ_ASSERT_RETURN(status == PJ_SUCCESS, 1);

    /* Must create a pool factory before we can allocate any memory. */
    pj_caching_pool_init(&cp, &pj_pool_factory_default_policy, 0);

    /* 
     * Initialize media endpoint.
     * This will implicitly initialize PJMEDIA too.
     */
    status = pjmedia_endpt_create(&cp.factory, NULL, 1, &med_endpt);
    PJ_ASSERT_RETURN(status == PJ_SUCCESS, 1);

    /* Create memory pool for our file player */
    pool = pj_pool_create( &cp.factory,	    /* pool factory	    */
			   "wav",	    /* pool name.	    */
			   4000,	    /* init size	    */
			   4000,	    /* increment size	    */
			   NULL		    /* callback on error    */
			   );

    /* Create file media port from the WAV file */
    status = pjmedia_file_player_port_create( pool,	/* memory pool	    */
					      argv[1],	/* file to play	    */
					      0,	/* flags	    */
					      0,	/* default buffer   */
					      NULL,	/* user data	    */
					      &file_port/* returned port    */
					      );
    if (status != PJ_SUCCESS) {
	app_perror(THIS_FILE, "Unable to use WAV file", status);
	return 1;
    }

    /* Create sound player port. */
    status = pjmedia_snd_port_create_player( 
		 pool,				    /* pool		    */
		 -1,				    /* use default dev.	    */
		 file_port->info.sample_rate,	    /* clock rate.	    */
		 file_port->info.channel_count,	    /* # of channels.	    */
		 file_port->info.samples_per_frame, /* samples per frame.   */
		 file_port->info.bits_per_sample,   /* bits per sample.	    */
		 0,				    /* options		    */
		 &snd_port			    /* returned port	    */
		 );
    if (status != PJ_SUCCESS) {
	app_perror(THIS_FILE, "Unable to open sound device", status);
	return 1;
    }

    /* Connect file port to the sound player.
     * Stream playing will commence immediately.
     */
    status = pjmedia_snd_port_connect( snd_port, file_port);
    PJ_ASSERT_RETURN(status == PJ_SUCCESS, 1);



    /* 
     * File should be playing and looping now, using sound device's thread. 
     */


    /* Sleep to allow log messages to flush */
    pj_thread_sleep(100);


    printf("Playing %s..\n", argv[1]);
    puts("");
    puts("Press <ENTER> to stop playing and quit");

    fgets(tmp, sizeof(tmp), stdin);

    
    /* Start deinitialization: */

    /* Destroy sound device */
    status = pjmedia_snd_port_destroy( snd_port );
    PJ_ASSERT_RETURN(status == PJ_SUCCESS, 1);


    /* Destroy file port */
    status = pjmedia_port_destroy( file_port );
    PJ_ASSERT_RETURN(status == PJ_SUCCESS, 1);


    /* Release application pool */
    pj_pool_release( pool );

    /* Destroy media endpoint. */
    pjmedia_endpt_destroy( med_endpt );

    /* Destroy pool factory */
    pj_caching_pool_destroy( &cp );


    /* Done. */
    return 0;
}
