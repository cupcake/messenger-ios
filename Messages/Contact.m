//
//  Contact.m
//  Messages
//
//  Created by Jesse Stuart on 7/28/13.
//  Copyright (c) 2013 Boolean Cupcake, LLC. All rights reserved.
//

#import "Contact.h"
#import "Conversation.h"
#import "Message.h"
#import "AppDelegate.h"
#import "Cursors.h"
#import "TentClient.h"
#import "TCPost+CoreData.h"

@implementation Contact

@dynamic avatar;
@dynamic name;
@dynamic conversations;
@dynamic messages;
@dynamic sectionName;

+ (void)syncRelationships {
    Cursors *cursors = ((AppDelegate *)([UIApplication sharedApplication].delegate)).cursors;
    TCAppPost *appPost = [((AppDelegate *)([UIApplication sharedApplication].delegate)) currentAppPost];

    TCParams *feedParams = [TCParams paramsWithDictionary:@{
                                                            @"types": @[@"https://tent.io/types/relationship/v0"],
                                                            @"entities": [appPost.entityURI absoluteString],
                                                            @"profiles": @"mentions"
                                                            }];

    // since cursor
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    NSString *sinceParameter = [formatter stringFromNumber:[NSNumber numberWithDouble:[cursors.relationshipCursorTimestamp timeIntervalSince1970] * 1000]];

    if (![cursors.relationshipCursorVersionID isEqualToString:@""]) {
        [feedParams addValue:[sinceParameter stringByAppendingString:[NSString stringWithFormat:@" %@", cursors.relationshipCursorVersionID]] forKey:@"since"];
    } else {
        [feedParams addValue:sinceParameter forKey:@"since"];
    }

    TentClient *client = [TentClient clientWithEntity:appPost.entityURI];
    NSError *error;
    client.metaPost = [[self applicationDelegate] fetchMetaPostForEntity:[appPost.entityURI absoluteString] error:&error];
    client.credentialsPost = appPost.authCredentialsPost;

    __block BOOL syncComplete = NO;

    [self fetchRelationshipsWithClient:client feedParams:feedParams successBlock:^(AFHTTPRequestOperation *operation, TCResponseEnvelope *responseEnvelope) {

        NSOperationQueue *fetchAvatarsQueue = [[NSOperationQueue alloc] init];
        [fetchAvatarsQueue setSuspended:YES];

        if ([[responseEnvelope posts] count] == 0) return;

        __block NSError *error;

        NSManagedObjectContext *context = [[self applicationDelegate] managedObjectContext];

        NSDictionary *profiles = [responseEnvelope profiles];

        TCPost *firstPost = [[responseEnvelope posts] firstObject];
        NSDate *firstTimestamp = firstPost.publishedAt;
        NSString *firstVersionID = firstPost.versionID;

        [[responseEnvelope posts] enumerateObjectsUsingBlock:^(TCPost *post, NSUInteger idx, BOOL *stop) {
            NSString *entity = [((NSDictionary *)[post.mentions objectAtIndex:0]) objectForKey:@"entity"];
            NSDictionary *profile = [profiles objectForKey:entity];

            if (!profile) return;

            Contact *contact = [[Contact alloc] initWithEntity:[NSEntityDescription entityForName:@"Contact" inManagedObjectContext:context] insertIntoManagedObjectContext:context];

            contact.name = [profile objectForKey:@"name"];

            if (!contact.name) {
                contact.name = entity;
            }

            __block NSManagedObjectID *contactObjectID = contact.objectID;
            __block NSString *avatarDigest = [profile objectForKey:@"avatar_digest"];

            if (contactObjectID && avatarDigest) {
                [fetchAvatarsQueue addOperationWithBlock:^{
                    [self fetchAvatarWithContactObjectID:contactObjectID entity:entity avatarDigest:avatarDigest];
                }];
            }

            TCPostManagedObject *postManagedObject = [MTLManagedObjectAdapter managedObjectFromModel:post insertingIntoContext:context error:&error];

            [contact addRelationshipPostObject:postManagedObject];
        }];

        if (![context hasChanges]) return;

        if ([[self applicationDelegate] saveContext:context error:&error]) {
            cursors.relationshipCursorTimestamp = firstTimestamp;
            cursors.relationshipCursorVersionID = firstVersionID;

            [cursors saveToPlistWithError:&error];
        }

        [fetchAvatarsQueue setSuspended:NO];
    } completionBlock:^{
        syncComplete = YES;
    }];

    // Wait for all requests to finish
    [client.operationQueue addOperationWithBlock:^{
        while (!syncComplete) {
            [NSThread sleepForTimeInterval:1];
        }
    }];

    [client.operationQueue waitUntilAllOperationsAreFinished];
}

+ (void)fetchRelationshipsWithClient:(TentClient *)client feedParams:(TCParams *)feedParams successBlock:(void (^)(AFHTTPRequestOperation *operation, TCResponseEnvelope *responseEnvelope))success completionBlock:(void (^)())completion {

    [client postsFeedWithParams:feedParams successBlock:^(AFHTTPRequestOperation *operation, TCResponseEnvelope *responseEnvelope) {
        success(operation, responseEnvelope);

        if ([responseEnvelope isEmpty]) {
            completion();
        } else {
            TCParams *prevPageParams = [responseEnvelope previousPageParams];

            [self fetchRelationshipsWithClient:client feedParams:prevPageParams successBlock:success completionBlock:completion];
        }
    } failureBlock:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"postsFeedWithParams failure: %@", error);
    }];
}

+ (void)fetchAvatarWithContactObjectID:(NSManagedObjectID *)contactObjectID entity:(NSString *)entity avatarDigest:(NSString *)avatarDigest {
    TCAppPost *appPost = [((AppDelegate *)([UIApplication sharedApplication].delegate)) currentAppPost];

    TentClient *client = [TentClient clientWithEntity:appPost.entityURI];

    NSError *error;

    client.metaPost = [[self applicationDelegate] fetchMetaPostForEntity:[appPost.entityURI absoluteString] error:&error];
    client.credentialsPost = appPost.authCredentialsPost;

    [client getAttachmentWithEntity:entity digest:avatarDigest successBlock:^(AFHTTPRequestOperation *operation, NSData *attachmentBinary) {
        NSManagedObjectContext *context = [[self applicationDelegate] managedObjectContext];

        Contact *contact = (Contact *)[context objectWithID:contactObjectID];

        contact.avatar = attachmentBinary;

        [[self applicationDelegate] saveContext:context error:nil];
    } failureBlock:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"fetch avatar failure: %@", error);
    }];

    [client.operationQueue waitUntilAllOperationsAreFinished];
}

+ (AppDelegate *)applicationDelegate {
    return (AppDelegate *)([UIApplication sharedApplication].delegate);
}

@end
