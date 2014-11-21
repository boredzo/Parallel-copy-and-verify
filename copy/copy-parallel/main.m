//
//  main.m
//  copy-parallel
//
//  Created by Peter Hosey on 2014-11-02.
//  Copyright (c) 2014 Peter Hosey. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <sysexits.h>

#define MILLIONS(a,b,c) a##b##c
static const size_t kBufferSize = MILLIONS(10,000,000);

#define ONE_MINUTE_NSEC (60 * NSEC_PER_SEC)

static bool verbose = false;

int main(int argc, char *argv[]) {
	if (argc > 1 && strcmp(argv[1], "--verbose") == 0) {
		verbose = true;
	}
	if (argc < 3 || argc > 5) {
		bool justAskingForHelp = (argc <= 1);
		fprintf(justAskingForHelp ? stdout : stderr,
			"Usage: %s in-file out-file\n",
			argv[0] ?: "copy-parallel");
		return justAskingForHelp ? EXIT_SUCCESS : EXIT_FAILURE;
	}

	@autoreleasepool {
		dispatch_queue_t writeQueue = dispatch_queue_create("write queue", DISPATCH_QUEUE_SERIAL);
		dispatch_queue_t logQueue = dispatch_queue_create("log queue", DISPATCH_QUEUE_SERIAL);

		void *buffers[2] = {
			malloc(kBufferSize),
			malloc(kBufferSize)
		};
		int currentBufferIdx = 0;

		dispatch_semaphore_t semaphore = dispatch_semaphore_create(1);

		int inFD = open(argv[1], O_RDONLY);
		int outFD = open(argv[2], O_WRONLY | O_TRUNC | O_EXLOCK);

		fcntl(inFD, F_NOCACHE, 1);
		fcntl(inFD, F_RDAHEAD, 1);
		fcntl(outFD, F_NOCACHE, 1);

		__block unsigned long long totalAmountWritten = 0;
		NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
		__block NSTimeInterval lastRateLogDate = 0.0;

		dispatch_group_t group = dispatch_group_create();

		int readNumber = 0;
		int writeNumber = 0;
		ssize_t amtRead;
		while (0 < (amtRead = read(inFD, buffers[currentBufferIdx], kBufferSize))) {
			const void *currentBuffer = buffers[currentBufferIdx];
			currentBufferIdx = ! currentBufferIdx;

			if (verbose) {
				++readNumber;
				dispatch_sync(logQueue, ^{
					fprintf(stderr, "Read number #%d; first bytes are 0x%02x%02x%02x%02x\n",
						readNumber,
						((const char *)currentBuffer)[0], ((const char *)currentBuffer)[1], ((const char *)currentBuffer)[2], ((const char *)currentBuffer)[3]
					);
				});
				++writeNumber;
			}
			dispatch_group_async(group, writeQueue, ^{
				if (verbose) {
					dispatch_sync(logQueue, ^{
						fprintf(stderr, "Write number #%d; first bytes are 0x%02x%02x%02x%02x\n",
							writeNumber,
							((const char *)currentBuffer)[0], ((const char *)currentBuffer)[1], ((const char *)currentBuffer)[2], ((const char *)currentBuffer)[3]
						);
					});
				}
				size_t portionOfReadWritten = 0;
				ssize_t amtWritten;
				const void *bytesYetToBeWritten = currentBuffer;
				size_t numBytesYetToBeWritten = (size_t)amtRead;
				while (0 < (amtWritten = write(outFD, bytesYetToBeWritten, numBytesYetToBeWritten))) {
					portionOfReadWritten += (size_t)amtWritten;
					bytesYetToBeWritten += amtWritten;
					numBytesYetToBeWritten -= (size_t)amtWritten;
					if (portionOfReadWritten == (size_t)amtRead) {
						break;
					}
				}
				totalAmountWritten += portionOfReadWritten;

				if (amtWritten < 0) {
					int writeError = errno;
					dispatch_sync(logQueue, ^{
						fprintf(stderr, "Error during write: %s\n", strerror(writeError));
						exit(EX_IOERR);
					});
				}
				dispatch_semaphore_signal(semaphore);

				NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
				if (now - lastRateLogDate > 2.0) {
					dispatch_async(logQueue, ^{
						fprintf(stderr, "Bytes copied so far: %'llu.\nTime so far: %f seconds.\nCurrent rate: %f bytes per second.\n",
							totalAmountWritten,
							now - start,
							totalAmountWritten / (now - start)
						);
						lastRateLogDate = now;
					});
				}
			});
			if (0 != dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, ONE_MINUTE_NSEC))) {
				fprintf(stderr, "Timed out waiting for write.\n");
				exit(EX_IOERR);
			}
		}

		//Free the buffers on the (serial) write queue so that we know all writes have completed by then.
		void *bufferOnTheLeft = buffers[0];
		void *bufferOnTheRight = buffers[1];
		dispatch_group_async(group, writeQueue, ^{
			free(bufferOnTheLeft);
			free(bufferOnTheRight);
		});
		dispatch_group_wait(group, ONE_MINUTE_NSEC);
	}
    return EXIT_SUCCESS;
}

