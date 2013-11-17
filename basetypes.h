/* basetypes.h

Copyright (c) 2013, Nikolaj Schlej. All rights reserved.
This program and the accompanying materials                          
are licensed and made available under the terms and conditions of the BSD License         
which accompanies this distribution.  The full text of the license may be found at        
http://opensource.org/licenses/bsd-license.php                                            

THE PROGRAM IS DISTRIBUTED UNDER THE BSD LICENSE ON AN "AS IS" BASIS,                     
WITHOUT WARRANTIES OR REPRESENTATIONS OF ANY KIND, EITHER EXPRESS OR IMPLIED.             

*/

#ifndef __BASETYPES_H__
#define __BASETYPES_H__

#include <stdarg.h>
#include <stdint.h>

typedef uint8_t   BOOLEAN;
typedef int8_t    INT8;
typedef uint8_t   UINT8;
typedef int16_t   INT16;
typedef uint16_t  UINT16;
typedef int32_t   INT32;
typedef uint32_t  UINT32;
typedef int64_t   INT64;
typedef uint64_t  UINT64;
typedef char      CHAR8;
typedef uint16_t  CHAR16;

#define CONST  const
#define VOID   void
#define STATIC static

#ifndef TRUE
#define TRUE  ((BOOLEAN)(1==1))
#endif

#ifndef FALSE
#define FALSE ((BOOLEAN)(0==1))
#endif

#ifndef NULL
#define NULL  ((VOID *) 0)
#endif

#if _MSC_EXTENSIONS
  //
  // Microsoft* compiler requires _EFIAPI usage, __cdecl is Microsoft* specific C.
  // 
  #define EFIAPI __cdecl  
#endif

#if __GNUC__
  #define EFIAPI __attribute__((cdecl))    
#endif

#define ERR_SUCCESS                         0
#define ERR_INVALID_PARAMETER               1
#define ERR_BUFFER_TOO_SMALL                2
#define ERR_OUT_OF_RESOURCES                3
#define ERR_OUT_OF_MEMORY                   4
#define ERR_FILE_OPEN                       5
#define ERR_FILE_READ                       6
#define ERR_FILE_WRITE                      7
#define ERR_ITEM_NOT_FOUND                  8
#define ERR_UNKNOWN_ITEM_TYPE               9
#define ERR_INVALID_FLASH_DESCRIPTOR        10
#define ERR_INVALID_REGION                  11
#define ERR_EMPTY_REGION                    12
#define ERR_BIOS_REGION_NOT_FOUND           13
#define ERR_VOLUMES_NOT_FOUND               14
#define ERR_INVALID_VOLUME                  15
#define ERR_VOLUME_REVISION_NOT_SUPPORTED   16
#define ERR_VOLUME_GROW_FAILED              17
#define ERR_UNKNOWN_FFS                     18
#define ERR_INVALID_FILE                    19
#define ERR_INVALID_SECTION                 20
#define ERR_UNKNOWN_SECTION                 21
#define ERR_STANDARD_COMPRESSION_FAILED     22
#define ERR_CUSTOMIZED_COMPRESSION_FAILED   23
#define ERR_STANDARD_DECOMPRESSION_FAILED   24
#define ERR_CUSTOMIZED_DECOMPRESSION_FAILED 25
#define ERR_UNKNOWN_COMPRESSION_ALGORITHM   26
#define ERR_UNKNOWN_EXTRACT_MODE            27
#define ERR_UNKNOWN_INSERT_MODE             28
#define ERR_NOT_IMPLEMENTED                 0xFF

// Compression algorithms
#define COMPRESSION_ALGORITHM_UNKNOWN 0
#define COMPRESSION_ALGORITHM_NONE    1
#define COMPRESSION_ALGORITHM_EFI11   2
#define COMPRESSION_ALGORITHM_TIANO   3
#define COMPRESSION_ALGORITHM_LZMA    4
#define COMPRESSION_ALGORITHM_IMLZMA  5

// Item extract modes
#define EXTRACT_MODE_AS_IS        0
#define EXTRACT_MODE_BODY_ONLY    1
#define EXTRACT_MODE_UNCOMPRESSED 2

// Item insert modes
#define INSERT_MODE_APPEND  0
#define INSERT_MODE_PREPEND 1
#define INSERT_MODE_BEFORE  2
#define INSERT_MODE_AFTER   3

// EFI GUID
typedef struct{
    UINT8 Data[16];
} EFI_GUID; 

#define ALIGN4(Value) (((Value)+3) & ~3)
#define ALIGN8(Value) (((Value)+7) & ~7)

#include <assert.h>
#define ASSERT(x) assert(x)

#endif
