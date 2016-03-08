//
//  TLUIUtility.h
//  TLChat
//
//  Created by 李伯坤 on 16/2/10.
//  Copyright © 2016年 李伯坤. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface TLUIUtility : NSObject

+ (CGFloat)getTextHeightOfText:(NSString *)text
                          font:(UIFont *)font
                         width:(CGFloat)width;

+ (void)getGroupAvatarByGroupUsers:(NSArray *)users
                           success:(void (^)(NSString *avatarPath))success;

@end
