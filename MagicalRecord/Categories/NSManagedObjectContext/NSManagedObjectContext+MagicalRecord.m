//
//  NSManagedObjectContext+MagicalRecord.m
//
//  Created by Saul Mora on 11/23/09.
//  Copyright 2010 Magical Panda Software, LLC All rights reserved.
//

#import "CoreData+MagicalRecord.h"
#import <objc/runtime.h>

static NSString * const kMagicalRecordNSManagedObjectContextWorkingName = @"kNSManagedObjectContextWorkingName";

@interface NSManagedObjectContext (MagicalRecordInternal)

- (void) MR_mergeChangesFromNotification:(NSNotification *)notification;
- (void) MR_mergeChangesOnMainThread:(NSNotification *)notification;
+ (void) MR_setDefaultContext:(NSManagedObjectContext *)moc;
+ (void) MR_setRootSavingContext:(NSManagedObjectContext *)context;

@end

@implementation NSManagedObjectContext (MagicalRecord)

- (NSString *) MR_description;
{
    NSString *contextLabel = [NSString stringWithFormat:@"*** %@ ***", [self MR_workingName]];
    NSString *onMainThread = [NSThread isMainThread] ? @"*** MAIN THREAD ***" : @"*** BACKGROUND THREAD ***";

    return [NSString stringWithFormat:@"<%@ (%p): %@> on %@", NSStringFromClass([self class]), self, contextLabel, onMainThread];
}

- (NSString *) MR_parentChain;
{
    NSMutableString *familyTree = [@"\n" mutableCopy];
    NSManagedObjectContext *currentContext = self;
    do
    {
        [familyTree appendFormat:@"- %@ (%p) %@\n", [currentContext MR_workingName], currentContext, (currentContext == self ? @"(*)" : @"")];
    }
    while ((currentContext = [currentContext parentContext]));

    return [NSString stringWithString:familyTree];
}

+ (NSManagedObjectContext *) MR_defaultContext
{
    return [[MagicalRecord currentStack] mainContext];
}

+ (NSManagedObjectContext *) MR_rootSavingContext;
{
    return [[MagicalRecord currentStack] rootSavingContext];
}

+ (NSManagedObjectContext *) MR_workerContext;
{
    return [[MagicalRecord currentStack] workerContext];
}

+ (void) MR_resetDefaultContext
{
    void (^resetBlock)(void) = ^{
        [[NSManagedObjectContext MR_defaultContext] reset];
    };
    
    dispatch_async(dispatch_get_main_queue(), resetBlock);
}

+ (NSManagedObjectContext *) MR_contextWithoutParent;
{
    NSManagedObjectContext *context = [[self alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    return context;
}

+ (NSManagedObjectContext *) MR_context;
{
    NSManagedObjectContext *context = [[self alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [context setParentContext:[self MR_defaultContext]];
    return context;
}

+ (NSManagedObjectContext *) MR_contextWithParent:(NSManagedObjectContext *)parentContext;
{
    NSManagedObjectContext *context = [self MR_contextWithoutParent];
    [context setParentContext:parentContext];
    return context;
}

+ (NSManagedObjectContext *) MR_newMainQueueContext;
{
    NSManagedObjectContext *context = [[self alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    MRLog(@"Created Main Queue Context: %@", context);
    return context;
}

- (void) MR_setWorkingName:(NSString *)workingName;
{
    [[self userInfo] setObject:workingName forKey:kMagicalRecordNSManagedObjectContextWorkingName];
}

- (NSString *) MR_workingName;
{
    NSString *workingName = [[self userInfo] objectForKey:kMagicalRecordNSManagedObjectContextWorkingName];
    if (nil == workingName)
    {
        workingName = @"UNNAMED";
    }
    return workingName;
}


@end
