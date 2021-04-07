//
//  OAProgressTitleCell.h
//  OsmAnd
//
//  Created by Paul on 03.26.2021.
//  Copyright © 2020 OsmAnd. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface OAProgressTitleCell : UITableViewCell

@property (weak, nonatomic) IBOutlet UILabel *titleLabel;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *activityIndicator;

@end
