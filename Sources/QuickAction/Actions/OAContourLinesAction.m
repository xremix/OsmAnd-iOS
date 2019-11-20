//
//  OAContourLinesAction.m
//  OsmAnd Maps
//
//  Created by igor on 19.11.2019.
//  Copyright © 2019 OsmAnd. All rights reserved.
//

#import "OAContourLinesAction.h"
#import "OAAppSettings.h"

@implementation OAContourLinesAction

- (instancetype) init
{
    return [super initWithType:EOAQuickActionTypeToggleContourLines];
}

- (void)execute
{
    //OAAppSettings *settings = [OAAppSettings sharedManager];
    //settings.
//    if (settings.nightMode)
//        [settings setSettingAppMode:APPEARANCE_MODE_DAY];
//    else
//        [settings setSettingAppMode:APPEARANCE_MODE_NIGHT];
    NSLog(@"switching");
}

- (NSString *)getIconResName
{
    return @"ic_custom_contour_lines";
//    if ([OAAppSettings sharedManager].nightMode)
//        return @"ic_custom_sun";
//    return @"ic_custom_moon";
}

- (NSString *)getActionText
{
    return @"QAContourLines"; ////change && add
    //return OALocalizedString(@"quick_action_day_night_descr");
}

- (NSString *)getActionStateName
{
    return @"Contour Lines";
    //return [OAAppSettings sharedManager].nightMode ? OALocalizedString(@"day_mode") : OALocalizedString(@"night_mode");
}

@end
