//
//  main.m
//  verify-parallel
//
//  Created by Peter Hosey on 2014-11-08.
//  Copyright (c) 2014 Peter Hosey. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <sysexits.h>

#define MILLIONS(a,b,c) a##b##c

int main(int argc, char *argv[]) {
	@autoreleasepool {
		NSEnumerator *argsEnum = [[[NSProcessInfo processInfo] arguments] objectEnumerator];
		[argsEnum nextObject];
		NSString *leftDeviceName = [argsEnum nextObject];
		NSString *rightDeviceName = [argsEnum nextObject];
		if ( ! (leftDeviceName != NULL && rightDeviceName != NULL) ) {
			fprintf(stderr, "Usage: %s file1 file2\n"
				"Reports whether any part of the two files (or of their common prefix, if one is shorter) differs.\n"
				"Exits with status 0 if no difference, 1 if a difference is found.\n",
				argv[0] ?: "verify-parallel"
			);
			return EX_USAGE;
		}

		NSFileHandle *leftFH = [NSFileHandle fileHandleForReadingAtPath:leftDeviceName];
		fcntl(leftFH.fileDescriptor, F_NOCACHE, 1);
		fcntl(leftFH.fileDescriptor, F_RDAHEAD, 1);
		NSFileHandle *rightFH = [NSFileHandle fileHandleForReadingAtPath:rightDeviceName];
		fcntl(rightFH.fileDescriptor, F_NOCACHE, 1);
		fcntl(rightFH.fileDescriptor, F_RDAHEAD, 1);

		static const unsigned long long int chunkSize = MILLIONS(10,000,000);

		dispatch_queue_t verifyQueue = dispatch_queue_create("verify queue", DISPATCH_QUEUE_SERIAL);
		dispatch_queue_t ioQueue = dispatch_queue_create("I/O queue", DISPATCH_QUEUE_CONCURRENT);
		dispatch_queue_t iterationQueue = dispatch_queue_create("iteration queue", DISPATCH_QUEUE_SERIAL);

		NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];

		__block bool keepReading = true;
		__block NSUInteger comparedSoFar = 0;
		while (keepReading) {
			dispatch_sync(iterationQueue, ^(){
				__block NSData *leftData = nil;
				__block NSData *rightData = nil;

				@autoreleasepool {
					dispatch_group_t group = dispatch_group_create();
					dispatch_group_async(group, ioQueue, ^{
						leftData = [leftFH readDataOfLength:chunkSize];
					});
					dispatch_group_async(group, ioQueue, ^{
						rightData = [rightFH readDataOfLength:chunkSize];
					});
					dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

					NSUInteger leftChunkSize = leftData.length;
					NSUInteger rightChunkSize = rightData.length;
					if (leftChunkSize == 0 || rightChunkSize == 0) {
						keepReading = false;
					}
					if (leftChunkSize < rightChunkSize) {
						rightData = [rightData subdataWithRange:(NSRange){ 0, leftChunkSize }];
						rightChunkSize = leftChunkSize;
						//TODO: Seek rightFH to leftFH's tell
					} else if (rightChunkSize < leftChunkSize) {
						leftData = [leftData subdataWithRange:(NSRange){ 0, rightChunkSize }];
						leftChunkSize = rightChunkSize;
						//TODO: Seek leftFH to rightFH's tell
					}

					//For capturing
					NSUInteger comparedSoFarAtThisPoint = comparedSoFar;
					comparedSoFar += leftChunkSize;

					NSData *leftDataCaptured = leftData;
					NSData *rightDataCaptured = rightData;
					dispatch_async(verifyQueue, ^{
						if ( ! [leftDataCaptured isEqualToData:rightDataCaptured] ) {
							fprintf(stderr, "VERIFICATION FAILED.\n"
								"At least one byte between %tu and %tu is different.\n"
								"Left file: %s\n"
								"Right file: %s\n",
								comparedSoFarAtThisPoint,
								comparedSoFarAtThisPoint + leftChunkSize,
								leftDeviceName.UTF8String,
								rightDeviceName.UTF8String
							);
							exit(EXIT_FAILURE);
						}
					});
				}
			});
		}

		dispatch_barrier_sync(verifyQueue, ^{
			fprintf(stderr, "Verification succeeded in %f seconds.\n"
				"Left file: %s\n"
				"Right file: %s\n",
				[NSDate timeIntervalSinceReferenceDate] - start,
				leftDeviceName.UTF8String,
				rightDeviceName.UTF8String
			);
		});
	}
    return EXIT_SUCCESS;
}

