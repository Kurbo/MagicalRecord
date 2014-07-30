//
//  NSManagedObjectContext+MagicalRecord.h
//
//  Created by Saul Mora on 11/23/09.
//  Copyright 2010 Magical Panda Software, LLC All rights reserved.
//

#import "MagicalRecord.h"

extern NSString * const kMagicalRecordDidMergeChangesFromiCloudNotification;

@interface NSManagedObjectContext (MagicalRecord)

+ (void) MR_resetDefaultContext;
+ (NSManagedObjectContext *) MR_rootSavingContext;
+ (NSManagedObjectContext *) MR_defaultContext;

- (NSString *) MR_description;
- (NSString *) MR_parentChain;

@property (nonatomic, copy, setter = MR_setWorkingName:) NSString *MR_workingName;

@end
