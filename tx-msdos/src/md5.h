#ifndef MD5_H
#define MD5_H

#include <stdio.h>
#include <ctype.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>

//----------------------------------------------------------------------------
//--------md5.h
//----------------------------------------------------------------------------

/* md5.h - Declaration of functions and data types used for MD5 sum
   computing library functions. */

//typedef unsigned long size_t;
typedef unsigned long md5_uint32;

/* Structure to save state of computation between the single steps.  */
typedef struct md5_ctx {
    md5_uint32 A;
    md5_uint32 B;
    md5_uint32 C;
    md5_uint32 D;

    md5_uint32 total[2];
    md5_uint32 buflen;
    unsigned char buffer[128];
} md5_ctx;

/*
 * The following three functions are build up the low level used in
 * the functions `md5_stream' and `md5_buffer'.
 */

/* Initialize structure containing state of computation.
   (RFC 1321, 3.3: Step 3)  */
void md5_init_ctx(md5_ctx* ctx);

/* Starting with the result of former calls of this function (or the
   initialization function update the context for the next LEN bytes
   starting at BUFFER.
   It is necessary that LEN is a multiple of 64!!! */
void md5_process_block(const void* buffer, size_t len,
    md5_ctx* ctx);

/* Process the remaining bytes in the buffer and put result from CTX
   in first 16 bytes following RESBUF.  The result is always in little
   endian byte order, so that a byte-wise output yields to the wanted
   ASCII representation of the message digest.

   IMPORTANT: On some systems it is required that RESBUF is correctly
   aligned for a 32 bits value.  */
void* md5_finish_ctx(md5_ctx* ctx, void* resbuf);

//----------------------------------------------------------------------------
//--------end of md5.h
//----------------------------------------------------------------------------

#endif // MD5_H