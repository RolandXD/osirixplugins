//
//  NSFileManager+DiscPublisher.m
//  Primiera
//
//  Created by Alessandro Volz on 2/22/10.
//  Copyright 2010 OsiriX Team. All rights reserved.
//

#import "NSFileManager+DiscPublisher.h"


@implementation NSFileManager (DiscPublisher)

-(NSString*)findSystemFolderOfType:(int)folderType forDomain:(int)domain {
    FSRef folder;
    NSString* result = NULL;
	
    OSErr err = FSFindFolder(domain, folderType, false, &folder);
    if (err == noErr) {
        CFURLRef url = CFURLCreateFromFSRef(kCFAllocatorDefault, &folder);
        result = [(NSURL*)url path];
		CFRelease(url);
    } else [NSException raise:NSGenericException format:@"FSFindFolder error %d", err];
	
    return result;
}

-(NSString*)tmpFilePathInDir:(NSString*)dirPath {
	NSString* prefix = [NSString stringWithFormat:@"%@_%@_%u_%x_", [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString*)kCFBundleNameKey], [[NSDate date] descriptionWithCalendarFormat:@"%Y%m%d%H%M%S" timeZone:NULL locale:NULL], getpid(), [NSThread currentThread]];
	char* path = tempnam(dirPath.UTF8String, prefix.UTF8String);
	NSString* nsPath = [NSString stringWithUTF8String:path];
	free(path);
	return nsPath;
}

-(NSString*)tmpFilePathInTmp {
	return [self tmpFilePathInDir:@"/tmp"];
}

-(NSString*)confirmDirectoryAtPath:(NSString*)dirPath {
	BOOL isDir, create = NO;
	NSError* error = NULL;
	
	if (![self fileExistsAtPath:dirPath isDirectory:&isDir])
		create = YES;
	else if (!isDir) {
		[self removeItemAtPath:dirPath error:&error];
		if (error) [NSException raise:NSGenericException format:@"Couldn't unlink file: %@", [error localizedDescription]];
		create = YES;
	}
	
	if (create) {
		[self createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:NULL error:&error];
		if (error) [NSException raise:NSGenericException format:@"Couldn't create directory: %@", [error localizedDescription]];
	}
	
	return dirPath;
}

-(NSUInteger)sizeAtPath:(NSString*)path {
	FSRef fsRef;
	CFURLGetFSRef((CFURLRef)[NSURL fileURLWithPath:path], &fsRef);
	return [self sizeAtFSRef:&fsRef];
}

-(NSUInteger)sizeAtFSRef:(FSRef*)theFileRef {
	FSIterator thisDirEnum = NULL;
	NSUInteger totalSize = 0;

	FSCatalogInfo fetchedInfos;
	OSErr fsErr = FSGetCatalogInfo(theFileRef, kFSCatInfoDataSizes|kFSCatInfoRsrcSizes|kFSCatInfoNodeFlags, &fetchedInfos, NULL, NULL, NULL);
	if (fsErr == noErr)
		if (fetchedInfos.nodeFlags &kFSNodeIsDirectoryMask) {
			if (FSOpenIterator(theFileRef, kFSIterateFlat, &thisDirEnum) == noErr) {
				const ItemCount kMaxEntriesPerFetch = 256;
				ItemCount actualFetched;
				FSRef fetchedRefs[kMaxEntriesPerFetch];
				FSCatalogInfo fetchedInfos[kMaxEntriesPerFetch];
				
				OSErr fsErr = FSGetCatalogInfoBulk(thisDirEnum, kMaxEntriesPerFetch, &actualFetched, NULL, kFSCatInfoDataSizes|kFSCatInfoRsrcSizes|kFSCatInfoNodeFlags, fetchedInfos, fetchedRefs, NULL, NULL);
				while ((fsErr == noErr) || (fsErr == errFSNoMoreItems)) {
					for (ItemCount thisIndex = 0; thisIndex < actualFetched; thisIndex++)
						if (fetchedInfos[thisIndex].nodeFlags &kFSNodeIsDirectoryMask)
							totalSize += [self sizeAtFSRef:&fetchedRefs[thisIndex]];
						else {
							totalSize += fetchedInfos[thisIndex].dataLogicalSize;
							totalSize += fetchedInfos[thisIndex].rsrcLogicalSize;
						}
					if (fsErr == errFSNoMoreItems)
						break;
					else fsErr = FSGetCatalogInfoBulk(thisDirEnum, kMaxEntriesPerFetch, &actualFetched, NULL, kFSCatInfoDataSizes|kFSCatInfoRsrcSizes|kFSCatInfoNodeFlags, fetchedInfos, fetchedRefs, NULL, NULL);
				}
				
				FSCloseIterator(thisDirEnum);
			}
		} else {
			totalSize += fetchedInfos.dataLogicalSize;
			totalSize += fetchedInfos.rsrcLogicalSize;
		}

	return totalSize;
}

@end