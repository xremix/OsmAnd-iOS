//
//  OASelectSubcategoryViewController.m
//  OsmAnd
//
//  Created by Alexey Kulish on 29/12/2016.
//  Copyright © 2016 OsmAnd. All rights reserved.
//

#import "OASelectSubcategoryViewController.h"
#import "Localization.h"
#import "OAMultiselectableHeaderView.h"
#import "OAPOICategory.h"
#import "OAPOIType.h"
#import "OACustomSelectionButtonCell.h"
#import "OAMenuSimpleCell.h"
#import "OAColors.h"
#import "OAPOIUIFilter.h"
#import "OASearchResult.h"
#import "OASearchUICore.h"
#import "OASearchSettings.h"
#import "OAQuickSearchHelper.h"

#define kCellTypeSelectionButton @"OACustomSelectionButtonCell"
#define kCellTypeTitle @"OAMenuSimpleCell"

@interface OASelectSubcategoryViewController () <UITableViewDataSource, UITableViewDelegate, OAMultiselectableHeaderDelegate, UITextFieldDelegate>

@property (weak, nonatomic) IBOutlet UIView *navBar;
@property (weak, nonatomic) IBOutlet UITableView *tableView;
@property (weak, nonatomic) IBOutlet UILabel *titleLabel;
@property (weak, nonatomic) IBOutlet UIButton *backButton;
@property (weak, nonatomic) IBOutlet UIButton *applyButton;
@property (weak, nonatomic) IBOutlet UITextField *searchField;
@property (weak, nonatomic) IBOutlet UIButton *cancelSearchButton;
@property (weak, nonatomic) IBOutlet UIView *bottomView;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *searchFieldRightConstraint;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *tableBottomConstraint;

@end

@implementation OASelectSubcategoryViewController
{
    OASearchUICore *_core;
    OAPOICategory *_category;
    OAPOIUIFilter *_filter;
    NSArray<OAPOIType *> *_items;
    NSMutableArray<OAPOIType *> *_selectedItems;
    NSMutableArray<OAPOIType *> *_searchResult;
    BOOL _searchMode;
}

- (instancetype)initWithCategory:(OAPOICategory *)category filter:(OAPOIUIFilter *)filter
{
    self = [super init];
    if (self)
    {
        _core = [[OAQuickSearchHelper instance] getCore];
        _category = category;
        _filter = filter;
        [self initData];
    }
    return self;
}

- (void)initData
{
    if (_category)
    {
        NSSet<NSString *> *acceptedTypes = [[_filter getAcceptedTypes] objectForKey:_category];
        NSSet<NSString *> *acceptedSubtypes = [_filter getAcceptedSubtypes:_category];
        NSArray<OAPOIType *> *types = _category.poiTypes;

        _selectedItems = [NSMutableArray new];
        _items = [NSArray arrayWithArray:[types sortedArrayUsingComparator:^NSComparisonResult(OAPOIType * _Nonnull t1, OAPOIType * _Nonnull t2) {
            return [t1.nameLocalized localizedCaseInsensitiveCompare:t2.nameLocalized];
        }]];

        if (acceptedSubtypes == [OAPOIBaseType nullSet] || acceptedTypes.count == types.count)
            _selectedItems = [NSMutableArray arrayWithArray:_items];
        else
            for (OAPOIType *poiType in _items)
                if ([acceptedTypes containsObject:poiType.name])
                    [_selectedItems addObject:poiType];
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.editing = YES;
    self.tableView.tintColor = UIColorFromRGB(color_primary_purple);

    [self.tableView beginUpdates];
    for (NSInteger i = 0; i < _items.count; i++)
        if ([_selectedItems containsObject:_items[i]])
            [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0] animated:NO scrollPosition:UITableViewScrollPositionNone];
    [self.tableView endUpdates];

    _searchMode = NO;
    self.searchField.delegate = self;
    [self.searchField addTarget:self action:@selector(textViewDidChange:) forControlEvents:UIControlEventEditingChanged];
    [self updateSearchView:NO];
}

-(void)applyLocalization
{
    [self updateTextTitle];

    self.applyButton.titleLabel.text = OALocalizedString(@"shared_string_apply");
    self.cancelSearchButton.titleLabel.text = OALocalizedString(@"shared_string_cancel");
}

- (void)updateTextTitle
{
    if (_searchMode)
        self.titleLabel.text = OALocalizedString(@"shared_string_search");
    else if (_category)
        self.titleLabel.text = _category.nameLocalized;
    else
        self.titleLabel.text = @"";
}

- (void)updateApplyButton
{
    if (_searchMode) {
        self.bottomView.hidden = YES;
        self.applyButton.hidden = YES;
        self.tableBottomConstraint.constant = 0;
    } else {
        self.bottomView.hidden = NO;
        self.applyButton.hidden = NO;
        self.tableBottomConstraint.constant = 87;
    }
}

- (void)updateSearchView:(BOOL)searchMode
{
    UIView *searchLeftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 30, 20)];
    UIImageView *searchLeftImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
    UIImage *searchIcon = [[UIImage imageNamed:@"ic_custom_search"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    searchLeftImageView.image = searchIcon;
    searchLeftImageView.tintColor = searchMode ? UIColorFromRGB(profile_icon_color_outdated_light) : [UIColor colorWithWhite:1 alpha:0.5];
    searchLeftImageView.center = searchLeftView.center;
    [searchLeftView addSubview:searchLeftImageView];
    self.searchField.leftViewMode = UITextFieldViewModeAlways;
    self.searchField.leftView = searchLeftView;
    self.searchField.borderStyle = UITextBorderStyleNone;
    self.searchField.layer.cornerRadius = 10;
    UIFont *searchTextFont = [UIFont systemFontOfSize:17 weight:UIFontWeightRegular];
    UIColor *searchTextColor = [UIColor colorWithWhite:1 alpha:0.5];
    self.searchField.placeholder = searchMode ? @"" : OALocalizedString(@"shared_string_search");
    self.searchField.text = @"";
    self.searchField.font = searchTextFont;
    self.searchField.tintColor = UIColorFromRGB(color_footer_icon_gray);
    self.searchField.backgroundColor = searchMode ? [UIColor colorWithWhite:1 alpha:1] : [UIColor colorWithWhite:1 alpha:0.24];
    self.searchField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:self.searchField.placeholder attributes:@{NSFontAttributeName:searchTextFont, NSForegroundColorAttributeName: searchTextColor}];
    [self.searchField endEditing:YES];
    self.cancelSearchButton.hidden = !searchMode;
    self.searchFieldRightConstraint.constant = searchMode ? 76 : 16;
}

- (void)selectDeselectGroup:(id)sender
{
    BOOL shouldSelect = _selectedItems.count == 0;
    if (!shouldSelect)
        [_selectedItems removeAllObjects];
    else
        [_selectedItems addObjectsFromArray:_items];

    for (NSInteger i = 0; i < _items.count; i++)
    {
        if (shouldSelect)
            [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0] animated:NO scrollPosition:UITableViewScrollPositionNone];
        else
            [self.tableView deselectRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0] animated:NO];
    }
    [self.tableView beginUpdates];
    [self.tableView headerViewForSection:0].textLabel.text = [[NSString stringWithFormat:OALocalizedString(@"selected_of"), (int)_selectedItems.count, _items.count] upperCase];
    [self.tableView endUpdates];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)selectDeselectItem:(NSIndexPath *)indexPath
{
    if (_searchMode || (!_searchMode &&  indexPath.row > 0))
    {
        [self.tableView beginUpdates];
        OAPOIType *type = _searchMode && _searchResult.count > indexPath.row ? _searchResult[indexPath.row] : _items[indexPath.row - 1];
        if ([_selectedItems containsObject:type])
            [_selectedItems removeObject:type];
        else
            [_selectedItems addObject:type];
        [self.tableView headerViewForSection:indexPath.section].textLabel.text = [[NSString stringWithFormat:OALocalizedString(@"selected_of"), (int) _selectedItems.count, _items.count] upperCase];
        [self.tableView endUpdates];
        [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:indexPath.section], indexPath] withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (IBAction)onBackButtonClicked:(id)sender
{
    if (self.delegate)
        [self.delegate selectSubcategoryCancel];

    [self dismissViewController];
}

- (IBAction)onApplyButtonClicked:(id)sender
{
    if (self.delegate)
    {
        NSMutableSet<NSString *> *selectedKeys = [NSMutableSet set];
        for (OAPOIType *poiType in _selectedItems)
            [selectedKeys addObject:poiType.name];
        [self.delegate selectSubcategoryDone:_category keys:selectedKeys allSelected:_selectedItems.count == _items.count];
    }

    [self dismissViewController];
}

- (IBAction)onSearchCancelButtonClicked:(id)sender
{
    _searchMode = NO;
    _searchResult = [NSMutableArray new];
    [self updateTextTitle];
    [self updateSearchView:NO];
    [self updateApplyButton];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - UITextViewDelegate

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField
{
    [self updateSearchView:YES];
    return YES;
}

-(void)textViewDidChange:(UITextView *)textView
{
    if (textView.text.length == 0)
    {
        _searchMode = NO;
        [_core updateSettings:_core.getSearchSettings.resetSearchTypes];
    }
    else {
        _searchMode = YES;
        _searchResult = [NSMutableArray new];
        OASearchSettings *searchSettings = [[_core getSearchSettings] setSearchTypes:@[[OAObjectType withType:POI_TYPE]]];
        [_core updateSettings:searchSettings];
        [_core search:textView.text delayedExecution:YES matcher:[[OAResultMatcher<OASearchResult *> alloc] initWithPublishFunc:^BOOL(OASearchResult *__autoreleasing *object) {
            OASearchResult *obj = *object;
            if (obj.objectType == SEARCH_FINISHED)
            {
                OASearchResultCollection *currentSearchResult = [_core getCurrentSearchResult];
                NSMutableArray<OAPOIType *> *results = [NSMutableArray new];
                for (OASearchResult *result in currentSearchResult.getCurrentSearchResults)
                {
                    NSObject *poiObject = result.object;
                    if ([poiObject isKindOfClass:[OAPOIType class]]) {
                        OAPOIType *poiType = (OAPOIType *) poiObject;
                        if (!poiType.isAdditional)
                        {
                            if (poiType.category == _category || [_items containsObject:poiType])
                                [results addObject:poiType];
                            else
                                for (OAPOIType *item in _items)
                                    if ([item.name isEqualToString:poiType.name])
                                        [results addObject:item];
                        }
                    }
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    _searchResult = [NSMutableArray arrayWithArray:results];
                    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
                });
            }
            return YES;
        } cancelledFunc:^BOOL {
            return !_searchMode;
        }]];
    }
    [self updateTextTitle];
    [self updateApplyButton];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - UITableViewDataSource

-(UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.row == 0 && !_searchMode)
    {
        OACustomSelectionButtonCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellTypeSelectionButton];
        if (cell == nil)
        {
            NSArray *nib = [[NSBundle mainBundle] loadNibNamed:kCellTypeSelectionButton owner:self options:nil];
            cell = nib[0];
            cell.separatorInset = UIEdgeInsetsMake(0., 65., 0., 0.);
            cell.tintColor = UIColorFromRGB(color_primary_purple);
            UIView *bgColorView = [[UIView alloc] init];
            bgColorView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.0];
            [cell setSelectedBackgroundView:bgColorView];
        }
        if (cell)
        {
            NSString *selectionText = _selectedItems.count > 0 ? OALocalizedString(@"shared_string_deselect_all") : OALocalizedString(@"select_all");
            [cell.selectDeselectButton setTitle:selectionText forState:UIControlStateNormal];
            [cell.selectDeselectButton removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
            [cell.selectDeselectButton addTarget:self action:@selector(selectDeselectGroup:) forControlEvents:UIControlEventTouchUpInside];
            [cell.selectionButton removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
            [cell.selectionButton addTarget:self action:@selector(selectDeselectGroup:) forControlEvents:UIControlEventTouchUpInside];

            NSInteger selectedAmount = _selectedItems.count;
            if (selectedAmount > 0)
            {
                UIImage *selectionImage = selectedAmount < _items.count ? [UIImage imageNamed:@"ic_system_checkbox_indeterminate"] : [UIImage imageNamed:@"ic_system_checkbox_selected"];
                [cell.selectionButton setImage:selectionImage forState:UIControlStateNormal];
            }
            else
            {
                [cell.selectionButton setImage:nil forState:UIControlStateNormal];
            }
            return cell;
        }
    }
    else
    {
        OAMenuSimpleCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellTypeTitle];
        if (cell == nil)
        {
            NSArray *nib = [[NSBundle mainBundle] loadNibNamed:kCellTypeTitle owner:self options:nil];
            cell = nib[0];
            cell.separatorInset = UIEdgeInsetsMake(0.0, 65.0, 0.0, 0.0);
            cell.tintColor = UIColorFromRGB(color_primary_purple);
            UIView *bgColorView = [[UIView alloc] init];
            bgColorView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.0];
            [cell setSelectedBackgroundView:bgColorView];
        }
        if (cell)
        {
            OAPOIType *poiType = _searchMode && _searchResult.count > indexPath.row ? _searchResult[indexPath.row] : _items[indexPath.row - 1];
            BOOL selected = [_selectedItems containsObject:poiType];

            UIColor *selectedColor = selected ? UIColorFromRGB(color_chart_orange) : UIColorFromRGB(color_tint_gray);
            UIImage *poiIcon = [UIImage templateImageNamed:poiType.iconName];
            cell.imgView.image = poiIcon ? poiIcon : [UIImage templateImageNamed:@"ic_custom_search_categories"];
            cell.imgView.tintColor = selectedColor;

            if (poiIcon.size.width < cell.imgView.frame.size.width && poiIcon.size.height < cell.imgView.frame.size.height)
                cell.imgView.contentMode = UIViewContentModeCenter;
            else
                cell.imgView.contentMode = UIViewContentModeScaleAspectFit;

            cell.textView.text = poiType.nameLocalized ? poiType.nameLocalized : @"";
            cell.descriptionView.hidden = true;

            if ([cell needsUpdateConstraints])
                [cell updateConstraints];
            return cell;
        }
    }
    return nil;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (_searchMode || (!_searchMode &&  indexPath.row > 0))
    {
        OAPOIType *item = _searchMode && _searchResult.count > indexPath.row ? _searchResult[indexPath.row] : _items[indexPath.row - 1];
        BOOL selected = [_selectedItems containsObject:item];
        [cell setSelected:selected animated:NO];
        if (selected)
            [tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
        else
            [tableView deselectRowAtIndexPath:indexPath animated:NO];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (_searchMode || (!_searchMode &&  indexPath.row > 0))
        [self selectDeselectItem:indexPath];
    else
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (_searchMode || (!_searchMode &&  indexPath.row > 0))
        [self selectDeselectItem:indexPath];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (!_searchMode && section == 0)
        return [NSString stringWithFormat:OALocalizedString(@"selected_of"), (int)_selectedItems.count, _items.count];
    return nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _searchMode ? _searchResult.count : _items.count + 1;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return _searchMode || (!_searchMode && indexPath.row != 0);
}

@end
