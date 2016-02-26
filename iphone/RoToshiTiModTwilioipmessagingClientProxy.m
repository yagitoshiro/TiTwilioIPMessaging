/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2009-2016年 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */

#import "RoToshiTiModTwilioipmessagingClientProxy.h"

@implementation RoToshiTiModTwilioipmessagingClientProxy

-(void)dealloc
{
    RELEASE_TO_NIL(_myChannels);
    RELEASE_TO_NIL(_client);
    RELEASE_TO_NIL(_identity);
    RELEASE_TO_NIL(_token);
    [super dealloc];
}

-(void)_initWithProperties:(NSDictionary *)args
{
    _myChannels = [[NSMutableDictionary alloc] init];
    [self initClient:args];
}

-(void)addToMyChannels:(TWMChannel *)channel
{
    NSLog(@"[INFO] start add to my channels");
    if(nil == _myChannels){
        NSLog(@"[INFO] myChannels is nil");
        _myChannels = [[NSMutableDictionary alloc] init];
    }
    NSLog(@"[INFO] my channels");
    NSString *sid = [channel sid];
    NSLog(@"[INFO] set value to mychannels");
    [_myChannels setObject:channel forKey:sid];
    NSLog(@"[INFO] end");
}

-(void)initClient:(id)args
{
    ENSURE_SINGLE_ARG(args, NSDictionary);
    if([args objectForKey:@"token"]){
        _token = [args objectForKey:@"token"];
        TwilioAccessManager *am = [TwilioAccessManager accessManagerWithToken:_token delegate:self];
        _client = [TwilioIPMessagingClient ipMessagingClientWithAccessManager:am delegate:self];
    }else{
        [self initWithUrl: [args objectForKey:@"url"]];
    }
    if([args objectForKey:@"identity"]){
        _identity = [args objectForKey:@"identity"];
    }
    [super _initWithProperties:args];
}

-(void)initWithUrl:(NSString *)url
{
    //Only GET Request is supported. I'm a slacker.
    NSString *identifierForVendor = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    NSString *guru;
    if([url containsString:@"?"]){
        guru = @"&device=";
    }else{
        guru = @"?device=";
    }
    NSString *tokenEndpoint = [NSString stringWithFormat:@"%@%@%@", url, guru, identifierForVendor];
    
    dispatch_queue_t q_global = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_queue_t q_main   = dispatch_get_main_queue();
    dispatch_async(q_global, ^{
        NSData *jsonResponse = [NSData dataWithContentsOfURL:[NSURL URLWithString:tokenEndpoint]];
        dispatch_async(q_main, ^{
            if(jsonResponse){
                NSError *jsonError;
                NSDictionary *tokenResponse = [NSJSONSerialization JSONObjectWithData:jsonResponse
                                                                              options:kNilOptions
                                                                                error:&jsonError];
                if([NSJSONSerialization isValidJSONObject:tokenResponse]){
                    _identity = tokenResponse[@"identity"];
                    _token = tokenResponse[@"token"];
                    TwilioAccessManager *am = [TwilioAccessManager accessManagerWithToken:_token delegate:self];
                    _client = [TwilioIPMessagingClient ipMessagingClientWithAccessManager:am delegate:self];
                    NSDictionary *data = @{@"message": @"client is ready"};
                    [self fireEvent:@"ipm:ready" withObject:data];
                }else{
                    NSString *str = [NSString stringWithUTF8String:[jsonResponse bytes]];
                    NSDictionary *data = @{@"message": str};
                    [self fireEvent:@"ipm:error" withObject:data];
                }
            }
        });
    });
    
}

-(void)joinChannel:(id)args
{
    ENSURE_SINGLE_ARG(args, NSDictionary);
    [_client channelsListWithCompletion:^(TWMResult result, TWMChannels *channelsList) {
        TWMChannel *channel = [self getChannel:[args objectForKey:@"channel"] fromChannelList:channelsList];
        [channel joinWithCompletion:^(TWMResult result) {
            if(result == TWMResultSuccess){
                NSLog(@"[INFO] mychannel");
                [self addToMyChannels:channel];
                NSLog(@"[INFO] mychannel end");
                
                NSLog(@"[INFO] messages");
                NSArray *messages = channel.messages.allObjects;
                NSMutableArray *msgs = [[NSMutableArray alloc] init];
                NSLog(@"[INFO] messages ready");
                for (id message in messages) {
                    NSLog(@"[INFO] message found");
                    [msgs addObject:[self messageToDict:message]];
                }
                NSLog(@"[INFO] ready to respond");
                NSDictionary *data = @{@"messages": msgs, @"channel": [self channelToDict:channel]};
                KrollCallback *success = [args objectForKey:@"success"];
                NSLog(@"[INFO] finish");
                [self _fireEventToListener:@"success" withObject:data listener:success thisObject:nil];
            }else{
                if([args objectForKey:@"error"]){
                    KrollCallback *error = [args objectForKey:@"error"];
                    [self _fireEventToListener:@"error" withObject:nil listener:error thisObject:nil];
                }
            }
        }];
    }];
}

-(void)leaveChannel:(id)args
{
    ENSURE_SINGLE_ARG(args, NSDictionary);
    KrollCallback *success = [args objectForKey:@"success"];
    
    [_client channelsListWithCompletion:^(TWMResult result, TWMChannels *channelsList) {
        TWMChannel *channel = [self getChannel:[args objectForKey:@"channel"] fromChannelList:channelsList];
        [channel leaveWithCompletion:^(TWMResult result) {
            if(result == TWMResultSuccess){
                if(_myChannels && [_myChannels objectForKey:[channel sid]]){
                    [_myChannels removeObjectForKey:[channel sid]];
                }
                [self _fireEventToListener:@"success" withObject:nil listener:success thisObject:nil];
            }else{
                if([args objectForKey:@"error"]){
                    KrollCallback *error = [args objectForKey:@"error"];
                    [self _fireEventToListener:@"error" withObject:nil listener:error thisObject:nil];
                }
            }
        }];
    }];
}

-(void)createChannel:(id)args
{
    ENSURE_SINGLE_ARG(args, NSDictionary);
    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    if([args objectForKey:@"uniqueName"]){
        NSString *uniqueName = [args objectForKey:@"uniqueName"];
        options[TWMChannelOptionUniqueName] = uniqueName;
    }
    if([args objectForKey:@"friendlyName"]){
        NSString *friendlyName = [args objectForKey:@"friendlyName"];
        options[TWMChannelOptionFriendlyName] = friendlyName;
    }
    NSString *type = [args objectForKey:@"type"];
    if([type isEqualToString:@"private"]){
        options[TWMChannelOptionType] = @(TWMChannelTypePrivate);
    }else{
        options[TWMChannelOptionType] = @(TWMChannelTypePublic);
    }
    if([args objectForKey:@"options"]){
        NSDictionary *ops = [args objectForKey:@"options"];
        options[TWMChannelOptionAttributes] = ops;
    }
    
    [_client channelsListWithCompletion:^(TWMResult result, TWMChannels *channelsList) {
        [channelsList createChannelWithOptions:options completion:^(TWMResult result, TWMChannel *channel) {
            NSLog(@"[INFO] debug 9");
            KrollCallback *success = [args objectForKey:@"success"];
            if(result == TWMResultSuccess){
                
                
                NSLog(@"[INFO] debug 10");
                NSDictionary *channelData = [self channelToDict:channel];

                NSLog(@"[INFO] debug 11");
                [self _fireEventToListener:@"success" withObject:channelData listener:success thisObject:nil];
                NSLog(@"[INFO] debug 12");
            }else{
                NSLog(@"[INFO] debug 13");
                if([args objectForKey:@"error"]){
                    KrollCallback *error = [args objectForKey:@"error"];
                    [self _fireEventToListener:@"error" withObject:nil listener:error thisObject:nil];
                    NSLog(@"[INFO] debug 14");
                }
            }
        }];
    }];
    
}

-(void)destroyChannel:(id)args
{
    ENSURE_SINGLE_ARG(args, NSDictionary);
    [_client channelsListWithCompletion:^(TWMResult result, TWMChannels *channelsList) {
        TWMChannel *channel = [self getChannel:[args objectForKey:@"channel"] fromChannelList:channelsList];
        NSString *sid = [channel sid];
        [channel destroyWithCompletion:^(TWMResult result) {
            KrollCallback *success = [args objectForKey:@"success"];
            if(_myChannels && [_myChannels objectForKey:sid]){
                [_myChannels removeObjectForKey:sid];
            }
            if(result == TWMResultSuccess){
                [self _fireEventToListener:@"success" withObject:nil listener:success thisObject:nil];
            }else{
                if([args objectForKey:@"error"]){
                    KrollCallback *error = [args objectForKey:@"error"];
                    [self _fireEventToListener:@"error" withObject:nil listener:error thisObject:nil];
                }
            }
        }];
    }];
}

-(void)getChannelList:(id)args
{
    ENSURE_SINGLE_ARG(args, NSDictionary);
    [_client channelsListWithCompletion:^(TWMResult result, TWMChannels *channelsList) {
        if(result == TWMResultSuccess){
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [channelsList loadChannelsWithCompletion:^(TWMResult result) {
                    NSLog(@"retrieve channel list start");
                    NSMutableArray *list = [[NSMutableArray alloc] init];
                    for (id channel in [channelsList allObjects]) {
                        if(channel){
                            NSLog(@"add channel to list");
                            [list addObject:[self channelToDict:channel]];
                            NSInteger status = [channel status];
                            if(status == TWMChannelStatusJoined){
                                NSLog(@"add channel to myChannels");
                                NSLog(@"[INFO] channel sid: %@", [channel sid]);
                                [self addToMyChannels:channel];
                            }
                        }
                    }
                    if(list){
                        KrollCallback *success = [args objectForKey:@"success"];
                        NSDictionary *data = @{@"channels": list};
                        [self _fireEventToListener:@"success" withObject:data listener:success thisObject:nil];
                    }else{
                        if([args objectForKey:@"error"]){
                            KrollCallback *error = [args objectForKey:@"error"];
                            NSDictionary *errorData = @{@"message": @"channels not found"};
                            [self _fireEventToListener:@"error" withObject:errorData listener:error thisObject:nil];
                        }
                    }
                }];
            });
        }
        
    }];
}

-(NSArray *)getMyChannels:(id)args
{
    return [_myChannels allKeys];
}

-(void)shutdown:(id)args
{
    [_client shutdown];
}

-(void)sendMessage:(id)args
{
    ENSURE_SINGLE_ARG(args, NSDictionary);
    TWMChannel *channel = [self getChannel:[args objectForKey:@"channel"]];
    if(channel){
        [self sendMessage:args toChannel:channel];
    }else{
        [_client channelsListWithCompletion:^(TWMResult result, TWMChannels *channelsList) {
            TWMChannel *channel = [self getChannel:[args objectForKey:@"channel"] fromChannelList:channelsList];
            if(channel){
                [self addToMyChannels:channel];
                [self sendMessage:args toChannel:channel];
            }else if([args objectForKey:@"error"]){
                KrollCallback *error = [args objectForKey:@"error"];
                NSDictionary *dict = @{@"message": @"channel not found"};
                [self _fireEventToListener:@"error" withObject:dict listener:error thisObject:nil];
            }
        }];
    }
}

-(void)sendMessage:(NSDictionary *)args toChannel:(TWMChannel*)channel
{
    TWMMessage *message = [channel.messages createMessageWithBody:[args objectForKey:@"message"]];
    [channel.messages sendMessage:message completion:^(TWMResult result) {
        if(result == TWMResultSuccess){
            KrollCallback *success = [args objectForKey:@"success"];
            [self _fireEventToListener:@"success" withObject:nil listener:success thisObject:nil];
        }else if([args objectForKey:@"error"]){
            KrollCallback *error = [args objectForKey:@"error"];
            [self _fireEventToListener:@"error" withObject:nil listener:error thisObject:nil];
        }
    }];
}

-(void)getMessages:(id)args
{
    ENSURE_SINGLE_ARG(args, NSDictionary);
    TWMChannel *channel = [self getChannel:[args objectForKey:@"channel"]];
    NSArray *messages = [channel.messages allObjects];
    NSMutableArray *list = [[NSMutableArray alloc] init];
    for(id message in messages){
        NSDictionary *msg = [self messageToDict:message];
        [list addObject:msg];
    }
    KrollCallback *success = [args objectForKey:@"success"];
    [self _fireEventToListener:@"success" withObject:list listener:success thisObject:nil];
}

-(void)addUser:(id)args
{
    ENSURE_SINGLE_ARG(args, NSDictionary);
    TWMChannel *channel = [self getChannel:[args objectForKey:@"channel"]];
    [channel.members addByIdentity:[args objectForKey:@"user"] completion:^(TWMResult result) {
        KrollCallback *success = [args objectForKey:@"success"];
        KrollCallback *error = [args objectForKey:@"error"];
        if(result == TWMResultSuccess){
            [self _fireEventToListener:@"success" withObject:nil listener:success thisObject:nil];
        }else{
            [self _fireEventToListener:@"error" withObject:nil listener:error thisObject:nil];
        }
    }];
}

-(void)removeUser:(id)args
{
    ENSURE_SINGLE_ARG(args, NSDictionary);
    TWMChannel *channel = [self getChannel:[args objectForKey:@"channel"]];
    [channel.members removeMember:[args objectForKey:@"user"] completion:^(TWMResult result) {
        KrollCallback *success = [args objectForKey:@"success"];
        KrollCallback *error = [args objectForKey:@"error"];
        if(result == TWMResultSuccess){
            [self _fireEventToListener:@"success" withObject:nil listener:success thisObject:nil];
        }else{
            [self _fireEventToListener:@"error" withObject:nil listener:error thisObject:nil];
        }
    }];
}

-(void)inviteUser:(id)args
{
    ENSURE_SINGLE_ARG(args, NSDictionary);
    TWMChannel *channel = [self getChannel:[args objectForKey:@"channel"]];
    [channel.members inviteByIdentity:[args objectForKey:@"user"] completion:^(TWMResult result) {
        KrollCallback *success = [args objectForKey:@"success"];
        KrollCallback *error = [args objectForKey:@"error"];
        if(result == TWMResultSuccess){
            [self _fireEventToListener:@"success" withObject:nil listener:success thisObject:nil];
        }else{
            [self _fireEventToListener:@"error" withObject:nil listener:error thisObject:nil];
        }
    }];
}

-(void)typing:(id)args
{
    TWMChannel *channel = [self getChannel:[args objectForKey:@"channel"]];
    [channel typing];
}

// TwilioIPMessagingClientDelegate
- (void)ipMessagingClient:(TwilioIPMessagingClient *)client channelAdded:(TWMChannel *)channel
{
    
}

- (void)ipMessagingClient:(TwilioIPMessagingClient *)client channelChanged:(TWMChannel *)channel
{
    
}

- (void)ipMessagingClient:(TwilioIPMessagingClient *)client channelDeleted:(TWMChannel *)channel
{
    
}

- (void)ipMessagingClient:(TwilioIPMessagingClient *)client channelHistoryLoaded:(TWMChannel *)channel
{
    
}

- (void)ipMessagingClient:(TwilioIPMessagingClient *)client channel:(TWMChannel *)channel memberJoined:(TWMMember *)member
{
    
}

- (void)ipMessagingClient:(TwilioIPMessagingClient *)client channel:(TWMChannel *)channel memberChanged:(TWMMember *)member
{
    
}

- (void)ipMessagingClient:(TwilioIPMessagingClient *)client channel:(TWMChannel *)channel memberLeft:(TWMMember *)member
{
    
}

- (void)ipMessagingClient:(TwilioIPMessagingClient *)client channel:(TWMChannel *)channel messageAdded:(TWMMessage *)message
{
    NSDictionary *messageData = [self messageToDict:message];
    NSDictionary *channelData = [self channelToDict:channel];
    NSDictionary *data = @{@"message": messageData, @"channel": channelData};
    [self fireEvent:@"messageAdded" withObject:data];
}

- (void)ipMessagingClient:(TwilioIPMessagingClient *)client channel:(TWMChannel *)channel messageChanged:(TWMMessage *)message
{
    NSDictionary *messageData = [self messageToDict:message];
    NSDictionary *channelData = [self channelToDict:channel];
    NSDictionary *data = @{@"message": messageData, @"channel": channelData};
    [self fireEvent:@"messageChanged" withObject:data];
}

- (void)ipMessagingClient:(TwilioIPMessagingClient *)client channel:(TWMChannel *)channel messageDeleted:(TWMMessage *)message
{
    NSDictionary *messageData = [self messageToDict:message];
    NSDictionary *channelData = [self channelToDict:channel];
    NSDictionary *data = @{@"message": messageData, @"channel": channelData};
    [self fireEvent:@"messageChanged" withObject:data];
}

- (void)ipMessagingClient:(TwilioIPMessagingClient *)client errorReceived:(TWMError *)error
{
    NSString *errorMessage;
    if([error localizedDescription]){
        errorMessage = [error localizedDescription];
    }else{
        errorMessage = @"unknown error";
    }
    [self fireEvent:@"clientError" withObject:@{@"message": errorMessage}];
}

- (void)ipMessagingClient:(TwilioIPMessagingClient *)client typingStartedOnChannel:(TWMChannel *)channel member:(TWMMember *)member
{
    
}

- (void)ipMessagingClient:(TwilioIPMessagingClient *)client typingEndedOnChannel:(TWMChannel *)channel member:(TWMMember *)member
{
    
}

- (void)ipMessagingClientToastSubscribed:(TwilioIPMessagingClient *)client
{
    
}

- (void)ipMessagingClient:(TwilioIPMessagingClient *)client toastReceivedOnChannel:(TWMChannel *)channel message:(TWMMessage *)message
{
    
}

- (void)ipMessagingClient:(TwilioIPMessagingClient *)client toastRegistrationFailedWithError:(TWMError *)error
{
    
}

-(void)accessManager:(TwilioAccessManager *)accessManager error:(NSError *)error
{
    NSLog(@"[INFO] access manager error");
    NSDictionary *dict = @{@"message": [error localizedDescription]};
    [self fireEvent:@"accessManagerError" withObject:dict];
}

-(void)accessManagerTokenExpired:(TwilioAccessManager *)accessManager
{
    NSLog(@"[INFO] access manager token expired");
    [accessManager updateToken:_token];
}

-(NSDictionary *)messageToDict:(TWMMessage*)message
{
    NSDictionary *messageData = @{
                                  @"sid": [self stringOrEmpty:[message sid]],
                                  @"author": [self stringOrEmpty:[message author]],
                                  @"body": [self stringOrEmpty:[message body]],
                                  @"timestamp": [self stringOrEmpty:[message timestamp]],
                                  @"dateUpdated": [self stringOrEmpty:[message dateUpdated]],
                                  @"lastUpdatedBy": [self stringOrEmpty:[message lastUpdatedBy]]
                                  };

    return messageData;
}

-(NSDictionary *)channelToDict:(TWMChannel *)channel
{
    NSString *typeString;
    if(TWMChannelTypePrivate ==[channel type]){
        typeString = @"private";
    }else{
        typeString = @"public";
    }
    NSInteger status = [channel status];
    NSString *statusString;
    if(status == TWMChannelStatusInvited){
        statusString = @"invited";
    }else if(status == TWMChannelStatusJoined){
        statusString = @"joined";
    }else if(status == TWMChannelStatusNotParticipating){
        statusString = @"participating";
    }
    NSDictionary *attrs;
    if([channel attributes]){
        attrs = [channel attributes];
    }else{
        attrs = @{};
    }
    NSDictionary *data = @{
                           @"friendlyName":[channel friendlyName],
                           @"uniqueName": [channel uniqueName],
                           @"sid": [channel sid],
                           @"type": typeString,
                           @"attributes": attrs,
                           @"status": statusString
                           };
    return data;
}

-(NSString *)stringOrEmpty:(NSString *)str
{
    if(!str){
        return @"";
    }else{
        return str;
    }
}

-(TWMChannel *)getChannel:(NSDictionary *)dict
{
    TWMChannel *channel;
    if([_myChannels objectForKey:[dict objectForKey:@"sid"]]){
        channel = [_myChannels objectForKey:[dict objectForKey:@"sid"]];
    }else{
        channel = nil;
    }
    return channel;
}

-(TWMChannel *)getChannel:(NSDictionary *)dict fromChannelList:(TWMChannels *)channelList
{
    TWMChannel *channel;
    if([dict objectForKey:@"sid"]){
        channel = [channelList channelWithId:[dict objectForKey:@"sid"]];
    }else if([dict objectForKey:@"uniqueName"]){
        channel = [channelList channelWithUniqueName:[[dict objectForKey:@"channel"] objectForKey:@"uniqueName"]];
    }
    return channel;
}

@end
