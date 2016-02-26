/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2009-2016年 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */
#import "TiProxy.h"
#import "TwilioIPMessagingClient/TwilioIPMessagingClient.h"

@interface RoToshiTiModTwilioipmessagingClientProxy : TiProxy <TwilioIPMessagingClientDelegate, TWMChannelDelegate, TwilioAccessManagerDelegate>
{
}
@property (strong, nonatomic) TwilioIPMessagingClient *client;
@property (strong, nonatomic) NSString *identity;
@property (strong, nonatomic) NSString *token;
@property (strong, nonatomic) NSMutableDictionary *myChannels;


@end
