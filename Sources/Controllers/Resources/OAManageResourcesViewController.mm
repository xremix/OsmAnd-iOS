//
//  OAManageResourcesViewController.mm
//  OsmAnd
//
//  Created by Alexey Pelykh on 7/15/14.
//  Copyright (c) 2014 OsmAnd. All rights reserved.
//

#import "OAManageResourcesViewController.h"

#import <Reachability.h>
#import <UIAlertView+Blocks.h>
#import <FFCircularProgressView.h>

#import "OsmAndApp.h"
#import "OAAutoObserverProxy.h"
#import "OATableViewCell.h"
#import "UITableViewCell+getTableView.h"
#import "OALocalResourceInformationViewController.h"
#import "OAWorldRegion.h"
#import "OALog.h"
#include "Localization.h"

#include <OsmAndCore/ResourcesManager.h>
#include <OsmAndCore/QKeyValueIterator.h>

typedef OsmAnd::ResourcesManager::ResourceType OsmAndResourceType;

#define kOpenSubregionSegue @"openSubregionSegue"

#define _(name) OAManageResourcesViewController__##name

#define ResourceItem _(ResourceItem)
@interface ResourceItem : NSObject
@property NSString* title;
@property QString resourceId;
@end
@implementation ResourceItem
@end

#define RepositoryResourceItem _(RepositoryResourceItem)
@interface RepositoryResourceItem : ResourceItem
@property std::shared_ptr<const OsmAnd::ResourcesManager::ResourceInRepository> resource;
@end
@implementation RepositoryResourceItem
@end

#define LocalResourceItem _(LocalResourceItem)
@interface LocalResourceItem : ResourceItem
@property std::shared_ptr<const OsmAnd::ResourcesManager::LocalResource> resource;
@end
@implementation LocalResourceItem
@end

#define OutdatedResourceItem _(OutdatedResourceItem)
@interface OutdatedResourceItem : LocalResourceItem
@end
@implementation OutdatedResourceItem
@end

@interface OAManageResourcesViewController () <UITableViewDelegate, UITableViewDataSource, UISearchDisplayDelegate>

@property (weak, nonatomic) IBOutlet UIView *scopeControlContainer;
@property (weak, nonatomic) IBOutlet UISegmentedControl *scopeControl;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *scopeControlContainerHeightConstraint;
@property (weak, nonatomic) IBOutlet UITableView *tableView;

@end

struct RegionResources
{
    QHash< QString, std::shared_ptr<const OsmAnd::ResourcesManager::Resource> > allResources;
    QHash< QString, std::shared_ptr<const OsmAnd::ResourcesManager::Resource> > repositoryResources;
    QHash< QString, std::shared_ptr<const OsmAnd::ResourcesManager::Resource> > localResources;
    QHash< QString, std::shared_ptr<const OsmAnd::ResourcesManager::Resource> > outdatedResources;
};

@implementation OAManageResourcesViewController
{
    OsmAndAppInstance _app;

    OAWorldRegion* _region;

    BOOL _dataInvalidated;
    NSObject* _dataLock;

    QHash< QString, std::shared_ptr<const OsmAnd::ResourcesManager::ResourceInRepository> > _resourcesInRepository;
    QHash< QString, std::shared_ptr<const OsmAnd::ResourcesManager::LocalResource> > _localResources;
    QHash< QString, std::shared_ptr<const OsmAnd::ResourcesManager::LocalResource> > _outdatedResources;
    QHash< OAWorldRegion* __weak, RegionResources > _resourcesByRegions;

    NSInteger _currentScope;

    NSInteger _lastUnusedSectionIndex;

    NSMutableArray* _searchableWorldwideRegionItems;

    NSInteger _subregionsSection;
    NSMutableArray* _searchableSubregionItems;
    NSMutableArray* _allSubregionItems;
    NSMutableArray* _repositorySubregionItems;
    NSMutableArray* _localSubregionItems;

    NSInteger _resourcesSection;
    NSMutableArray* _allResourceItems;
    NSMutableArray* _repositoryResourceItems;
    NSMutableArray* _localResourceItems;

    NSString* _lastSearchString;
    NSInteger _lastSearchScope;
    NSArray* _searchResults;

    CGFloat _originalScopeControlContainerHeight;

    NSComparator _resourceItemsComparator;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        _app = [OsmAndApp instance];

        _region = _app.worldRegion;
        _dataInvalidated = NO;
        _dataLock = [[NSObject alloc] init];

        _currentScope = 0;

        _searchableWorldwideRegionItems = [NSMutableArray array];

        _searchableSubregionItems = [NSMutableArray array];
        _allSubregionItems = [NSMutableArray array];
        _repositorySubregionItems = [NSMutableArray array];
        _localSubregionItems = [NSMutableArray array];
        _allResourceItems = [NSMutableArray array];
        _repositoryResourceItems = [NSMutableArray array];
        _localResourceItems = [NSMutableArray array];

        _lastSearchString = @"";
        _lastSearchScope = 0;
        _searchResults = nil;

        _resourceItemsComparator = ^NSComparisonResult(id obj1, id obj2) {
            ResourceItem *item1 = obj1;
            ResourceItem *item2 = obj2;

            return [item1.title localizedCaseInsensitiveCompare:item2.title];
        };
    }
    return self;
}

- (void)setupWithRegion:(OAWorldRegion*)region andWorldRegionItems:(NSArray*)worldRegionItems andScope:(NSInteger)scope
{
    _region = region;
    _searchableWorldwideRegionItems = [worldRegionItems copy];
    _currentScope = scope;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

#if defined(DEBUG)
    //HACK: This stuff is needed to avoid exceptions during Debug. In Release they're harmless
    self.searchDisplayController.searchBar.searchBarStyle = UISearchBarStyleDefault;
#endif // defined(DEBUG)

    if (_region != _app.worldRegion)
        self.title = _region.name;

    // Configure search scope
    if (_region == _app.worldRegion)
        self.searchDisplayController.searchBar.scopeButtonTitles = nil;
    else
        self.searchDisplayController.searchBar.scopeButtonTitles = @[_region.name, OALocalizedString(@"Worldwide")];

    _scopeControl.selectedSegmentIndex = _currentScope;

    _originalScopeControlContainerHeight = self.scopeControlContainerHeightConstraint.constant;

    [self obtainDataAndItems];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    if (_dataInvalidated)
    {
        [self updateContent];
        _dataInvalidated = NO;
    }
}

- (void)updateContent
{
    [self obtainDataAndItems];
    [self.tableView reloadData];
}

- (void)obtainDataAndItems
{
    @synchronized(_dataLock)
    {
        [self prepareData];
        [self collectSubregionsDataAndItems];
        [self collectResourcesDataAndItems];

        [self refreshContent];
    }
}

- (void)prepareData
{
    // Obtain all resources separately
    _resourcesInRepository = _app.resourcesManager->getResourcesInRepository();
    _localResources = _app.resourcesManager->getLocalResources();
    _outdatedResources = _app.resourcesManager->getOutdatedInstalledResources();

    // Collect resources for each region (worldwide)
    _resourcesByRegions.clear();
    NSArray* mergedRegions = [_app.worldRegion.flattenedSubregions arrayByAddingObject:_app.worldRegion];
    for(OAWorldRegion* region in mergedRegions)
    {
        const auto regionId = QString::fromNSString(region.regionId);
        const auto downloadsIdPrefix = QString::fromNSString(region.downloadsIdPrefix);

        RegionResources regionResources;
        for (const auto& resource : _outdatedResources)
        {
            if (!resource->id.startsWith(downloadsIdPrefix))
                continue;

            regionResources.allResources.insert(resource->id, resource);
            regionResources.outdatedResources.insert(resource->id, resource);
            regionResources.localResources.insert(resource->id, resource);
        }
        for (const auto& resource : _localResources)
        {
            if (!resource->id.startsWith(downloadsIdPrefix))
                continue;

            if (!regionResources.allResources.contains(resource->id))
                regionResources.allResources.insert(resource->id, resource);
            if (!regionResources.localResources.contains(resource->id))
                regionResources.localResources.insert(resource->id, resource);
        }
        for (const auto& resource : _resourcesInRepository)
        {
            if (!resource->id.startsWith(downloadsIdPrefix))
                continue;

            if (!regionResources.allResources.contains(resource->id))
                regionResources.allResources.insert(resource->id, resource);
            regionResources.repositoryResources.insert(resource->id, resource);
        }

        _resourcesByRegions.insert(region, regionResources);
    }
}

- (void)collectSubregionsDataAndItems
{
    // Collect all regions (and their parents) that have at least one
    // resource available in repository or locally.

    [_searchableSubregionItems removeAllObjects];
    [_allSubregionItems removeAllObjects];
    [_repositorySubregionItems removeAllObjects];
    [_localSubregionItems removeAllObjects];
    for(OAWorldRegion* subregion in _region.flattenedSubregions)
    {
        // Look in repository
        BOOL foundRepositoryResource = NO;
        for(const auto& resource : _resourcesInRepository)
        {
            OAWorldRegion* match = [OAManageResourcesViewController findRegionOrAnySubregionOf:subregion
                                                                          thatContainsResource:resource->id];
            if (!match)
                continue;

            OAWorldRegion* intermediateRegion = match;
            while (intermediateRegion != subregion && intermediateRegion != nil)
            {
                if (![_searchableSubregionItems containsObject:intermediateRegion])
                    [_searchableSubregionItems addObject:intermediateRegion];

                intermediateRegion = intermediateRegion.superregion;
            }

            foundRepositoryResource = YES;
            break;
        }

        // Look in local resources
        BOOL foundLocalResource = NO;
        for(const auto& resource : _localResources)
        {
            OAWorldRegion* match = [OAManageResourcesViewController findRegionOrAnySubregionOf:subregion
                                                                          thatContainsResource:resource->id];
            if (!match)
                continue;

            OAWorldRegion* intermediateRegion = match;
            while (intermediateRegion != subregion && intermediateRegion != nil)
            {
                if (![_searchableSubregionItems containsObject:intermediateRegion])
                    [_searchableSubregionItems addObject:intermediateRegion];

                intermediateRegion = intermediateRegion.superregion;
            }

            foundLocalResource = YES;
            break;
        }

        // If subregion has nothing to offer, skip it
        if (!foundRepositoryResource && !foundLocalResource)
        {
            OALog(@"Region %@ (%@) was skipped since it has no resources", subregion.name, subregion.regionId);
            continue;
        }

        if (![_searchableSubregionItems containsObject:subregion])
            [_searchableSubregionItems addObject:subregion];
        if (subregion.superregion == _region)
        {
            [_allSubregionItems addObject:subregion];
            if (foundRepositoryResource)
                [_repositorySubregionItems addObject:subregion];
            if (foundLocalResource)
                [_localSubregionItems addObject:subregion];
        }
    }
    [_searchableSubregionItems sortUsingSelector:@selector(compare:)];
    [_allSubregionItems sortUsingSelector:@selector(compare:)];
    [_repositorySubregionItems sortUsingSelector:@selector(compare:)];
    [_localSubregionItems sortUsingSelector:@selector(compare:)];
}

- (void)collectResourcesDataAndItems
{
    [_allResourceItems removeAllObjects];
    [_repositoryResourceItems removeAllObjects];
    [_localResourceItems removeAllObjects];

    const auto citRegionResources = _resourcesByRegions.constFind(_region);
    if (citRegionResources == _resourcesByRegions.cend())
        return;
    const auto& regionResources = *citRegionResources;

    for (const auto& resource_ : regionResources.allResources)
    {
        if (const auto resource = std::dynamic_pointer_cast<const OsmAnd::ResourcesManager::LocalResource>(resource_))
        {
            if (regionResources.outdatedResources.contains(resource->id))
            {
                OutdatedResourceItem* item = [[OutdatedResourceItem alloc] init];
                item.resourceId = resource->id;
                item.title = [self titleOfResource:resource_];
                item.resource = resource;

                if (item.title == nil)
                    continue;

                [_localResourceItems addObject:item];
                [_allResourceItems addObject:item];
            }
            else
            {
                LocalResourceItem* item = [[LocalResourceItem alloc] init];
                item.resourceId = resource->id;
                item.title = [self titleOfResource:resource_];
                item.resource = resource;

                if (item.title == nil)
                    continue;

                [_localResourceItems addObject:item];
                [_allResourceItems addObject:item];
            }
        }
        else if (const auto resource = std::dynamic_pointer_cast<const OsmAnd::ResourcesManager::ResourceInRepository>(resource_))
        {
            RepositoryResourceItem* item = [[RepositoryResourceItem alloc] init];
            item.resourceId = resource->id;
            item.title = [self titleOfResource:resource_];
            item.resource = resource;

            if (item.title == nil)
                continue;

            [_repositoryResourceItems addObject:item];
            [_allResourceItems addObject:item];
        }
    }
    [_allResourceItems sortUsingComparator:_resourceItemsComparator];
    [_repositoryResourceItems sortUsingComparator:_resourceItemsComparator];
    [_localResourceItems sortUsingComparator:_resourceItemsComparator];
}

- (void)refreshContent
{
    @synchronized(_dataLock)
    {
        _lastUnusedSectionIndex = 0;


        if ([[self getSubregionItems] count] > 0)
            _subregionsSection = _lastUnusedSectionIndex++;
        else
            _subregionsSection = -1;

        if ([[self getResourceItems] count] > 0)
            _resourcesSection = _lastUnusedSectionIndex++;
        else
            _resourcesSection = -1;

        [self.tableView reloadData];
    }
}

- (NSMutableArray*)getSubregionItems
{
    switch (_currentScope)
    {
        case 0:
            return _allSubregionItems;

        case 1:
            return _repositorySubregionItems;

        case 2:
            return _localSubregionItems;
    }

    return nil;
}

- (NSMutableArray*)getResourceItems
{
    switch (_currentScope)
    {
        case 0:
            return _allResourceItems;

        case 1:
            return _repositoryResourceItems;

        case 2:
            return _localResourceItems;
    }
    
    return nil;
}

- (NSString*)titleOfResource:(const std::shared_ptr<const OsmAnd::ResourcesManager::Resource>&)resource
{
    return [self titleOfResource:resource withRegionName:nil];
}

- (NSString*)titleOfResource:(const std::shared_ptr<const OsmAnd::ResourcesManager::Resource>&)resource
              withRegionName:(NSString*)regionName
{
    if (_region == _app.worldRegion)
    {
        if (resource->id == QLatin1String("world_basemap.map.obf"))
            return OALocalizedString(@"Detailed overview map");
        return nil;
    }

    switch(resource->type)
    {
        case OsmAndResourceType::MapRegion:
            if ([_region.subregions count] > 0)
            {
                if (regionName == nil)
                    return OALocalizedString(@"Full map of entire region");
                else
                    return OALocalizedString(@"Full map of entire %@", regionName);
            }
            else
            {
                if (regionName == nil)
                    return OALocalizedString(@"Full map of the region");
                else
                    return OALocalizedString(@"Full map of %@", regionName);
            }
            break;

        default:
            return nil;
    }
}

- (void)performSearchForSearchString:(NSString*)searchString
                      andSearchScope:(NSInteger)searchScope
{
    @synchronized(_dataLock)
    {
        // If case searchString is empty, there are no results
        if (searchString == nil || [searchString length] == 0)
        {
            _searchResults = @[];
            return;
        }

        // In case searchString has only spaces, also nothing to do here
        if ([[searchString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] == 0)
        {
            _searchResults = @[];
            return;
        }

        // Select where to look
        NSArray* searchableContent = nil;
        if (_region == _app.worldRegion || searchScope == 0)
            searchableContent = _searchableSubregionItems;
        else
            searchableContent = _searchableWorldwideRegionItems;

        // Search through subregions:

        NSComparator regionComparator = ^NSComparisonResult(id obj1, id obj2) {
            OAWorldRegion *item1 = obj1;
            OAWorldRegion *item2 = obj2;

            return [item1.name localizedCaseInsensitiveCompare:item2.name];
        };

        // Regions that start with given name have higher priority
        NSPredicate* startsWith = [NSPredicate predicateWithFormat:@"name BEGINSWITH[cd] %@", searchString];
        NSMutableArray *regions_startsWith = [[searchableContent filteredArrayUsingPredicate:startsWith] mutableCopy];
        if ([regions_startsWith count] == 0)
        {
            NSPredicate* anyStartsWith = [NSPredicate predicateWithFormat:@"ANY allNames BEGINSWITH[cd] %@", searchString];
            [regions_startsWith addObjectsFromArray:[searchableContent filteredArrayUsingPredicate:anyStartsWith]];
        }
        [regions_startsWith sortUsingComparator:regionComparator];

        // Regions that only contain given string have less priority
        NSPredicate* onlyContains = [NSPredicate predicateWithFormat:
                                     @"(name CONTAINS[cd] %@) AND NOT (name BEGINSWITH[cd] %@)",
                                     searchString,
                                     searchString];
        NSMutableArray *regions_onlyContains = [[searchableContent filteredArrayUsingPredicate:onlyContains] mutableCopy];
        if ([regions_onlyContains count] == 0)
        {
            NSPredicate* anyOnlyContains = [NSPredicate predicateWithFormat:
                                            @"(ANY allNames CONTAINS[cd] %@) AND NOT (ANY allNames BEGINSWITH[cd] %@)",
                                            searchString,
                                            searchString];
            [regions_onlyContains addObjectsFromArray:[searchableContent filteredArrayUsingPredicate:anyOnlyContains]];
        }
        [regions_onlyContains sortUsingComparator:regionComparator];

        // Assemble all regions all togather
        NSArray* regions = [regions_startsWith arrayByAddingObjectsFromArray:regions_onlyContains];
        NSMutableArray* results = [NSMutableArray array];
        for (OAWorldRegion* region in regions)
        {
            [results addObject:region];

            // Get all resources that are direct children of current region
            const auto citRegionResources = _resourcesByRegions.constFind(region);
            if (citRegionResources == _resourcesByRegions.cend())
                continue;
            const auto& regionResources = *citRegionResources;

            // Create items for each resource found
            NSMutableArray* resourceItems = [NSMutableArray array];
            for (const auto& resource_ : regionResources.allResources)
            {
                if (const auto resource = std::dynamic_pointer_cast<const OsmAnd::ResourcesManager::LocalResource>(resource_))
                {
                    if (regionResources.outdatedResources.contains(resource->id))
                    {
                        OutdatedResourceItem* item = [[OutdatedResourceItem alloc] init];
                        item.resourceId = resource->id;
                        item.title = [self titleOfResource:resource_
                                            withRegionName:region.name];
                        item.resource = resource;

                        if (item.title == nil)
                            continue;

                        [resourceItems addObject:item];
                    }
                    else
                    {
                        LocalResourceItem* item = [[LocalResourceItem alloc] init];
                        item.resourceId = resource->id;
                        item.title = [self titleOfResource:resource_
                                            withRegionName:region.name];
                        item.resource = resource;

                        if (item.title == nil)
                            continue;

                        [resourceItems addObject:item];
                    }
                }
                else if (const auto resource = std::dynamic_pointer_cast<const OsmAnd::ResourcesManager::ResourceInRepository>(resource_))
                {
                    RepositoryResourceItem* item = [[RepositoryResourceItem alloc] init];
                    item.resourceId = resource->id;
                    item.title = [self titleOfResource:resource_
                                        withRegionName:region.name];
                    item.resource = resource;

                    if (item.title == nil)
                        continue;

                    [resourceItems addObject:item];
                }
            }
            [resourceItems sortUsingComparator:_resourceItemsComparator];
            
            [results addObjectsFromArray:resourceItems];
        }
        
        _searchResults = results;
    }
}

- (void)onItemClicked:(id)item_
{
    if ([item_ isKindOfClass:[OutdatedResourceItem class]])
    {
        /*
         [[[UIAlertView alloc] initWithTitle:nil
         message:[NSString stringWithFormat:OALocalizedString(@"An update is available for %1$@. %2$@ will be downloaded. %3$@Proceed?"),
         itemName,
         [NSByteCountFormatter stringFromByteCount:item.resourceInRepository->packageSize
         countStyle:NSByteCountFormatterCountStyleFile],
         [Reachability reachabilityForInternetConnection].currentReachabilityStatus == ReachableViaWWAN ? OALocalizedString(@"HEY YOU'RE ON 3G!!! ") : @""]
         cancelButtonItem:[RIButtonItem itemWithLabel:OALocalizedString(@"Cancel")]
         otherButtonItems:[RIButtonItem itemWithLabel:OALocalizedString(@"Update")
         action:^{
         [self startDownloadOf:item];
         }], nil] show];
         */
    }
    else if ([item_ isKindOfClass:[LocalResourceItem class]])
    {
        LocalResourceItem* item = (LocalResourceItem*)item_;

        NSString* resourceId = item.resourceId.toNSString();
        [self.navigationController pushViewController:[[OALocalResourceInformationViewController alloc] initWithLocalResourceId:resourceId]
                                             animated:YES];
    }
    else if ([item_ isKindOfClass:[RepositoryResourceItem class]])
    {
        /*
         [self checkInternetConnection:[[UIAlertView alloc] initWithTitle:nil
         message:[NSString stringWithFormat:OALocalizedString(@"Installation of %1$@ requires %2$@ to be downloaded. %3$@Proceed?"),
         itemName,
         [NSByteCountFormatter stringFromByteCount:item.resourceInRepository->packageSize
         countStyle:NSByteCountFormatterCountStyleFile],
         [Reachability reachabilityForInternetConnection].currentReachabilityStatus == ReachableViaWWAN ? OALocalizedString(@"HEY YOU'RE ON 3G!!! ") : @""]
         cancelButtonItem:[RIButtonItem itemWithLabel:OALocalizedString(@"Cancel")]
         otherButtonItems:[RIButtonItem itemWithLabel:OALocalizedString(@"Install")
         action:^{
         [self startDownloadOf:item];
         }], nil]];
         */
    }

    /*
     if (indexPath.section != _downloadsSection)
     return;

     BaseDownloadItem* item = [_downloadItems objectAtIndex:indexPath.row];

     NSString* itemName = nil;
     if (_worldRegion.superregion == nil)
     itemName = [_tableView cellForRowAtIndexPath:indexPath].textLabel.text;
     else
     {
     itemName = [NSString stringWithFormat:OALocalizedString(@"%1$@ (%2$@)"),
     [_tableView cellForRowAtIndexPath:indexPath].textLabel.text,
     _worldRegion.name];
     }

     if ([item isKindOfClass:[OutdatedItem class]])
     {

     }
     else if ([item isKindOfClass:[InstalledItem class]])
     {

     }
     else if ([item isKindOfClass:[InstallableItem class]])
     {

     }
     else if ([item isKindOfClass:[DownloadedItem class]])
     {
     [self checkInternetConnection:[[UIAlertView alloc] initWithTitle:nil
     message:[NSString stringWithFormat:OALocalizedString(@"You're going to cancel download of %1$@. Are you sure?"),
     itemName]
     cancelButtonItem:[RIButtonItem itemWithLabel:OALocalizedString(@"Continue")]
     otherButtonItems:[RIButtonItem itemWithLabel:OALocalizedString(@"Cancel")
     action:^{
     [self cancelDownloadOf:item];
     }], nil]];
     }
     */
}

- (IBAction)onScopeChanged:(id)sender
{
    _currentScope = _scopeControl.selectedSegmentIndex;

    [self refreshContent];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    if (tableView == self.searchDisplayController.searchResultsTableView)
        return 1;

    NSInteger sectionsCount = 0;

    if (_subregionsSection >= 0)
        sectionsCount++;
    if (_resourcesSection >= 0)
        sectionsCount++;

    return sectionsCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (tableView == self.searchDisplayController.searchResultsTableView)
        return [_searchResults count];

    if (section == _subregionsSection)
        return [[self getSubregionItems] count];
    if (section == _resourcesSection)
        return [[self getResourceItems] count];

    return 0;
}

- (NSString*)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (tableView == self.searchDisplayController.searchResultsTableView)
        return nil;

    if (_region.superregion == nil)
    {
        if (section == _subregionsSection)
            return OALocalizedString(@"By regions");
        if (section == _resourcesSection)
            return OALocalizedString(@"Worldwide");
        return nil;
    }

    if (section == _subregionsSection)
        return OALocalizedString(@"Regions");
    if (section == _resourcesSection)
        return OALocalizedString(@"Maps & resources");

    return nil;
}

- (UITableViewCell*)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString* const subregionCell = @"subregionCell";
    static NSString* const outdatedResourceCell = @"outdatedResourceCell";
    static NSString* const localResourceCell = @"localResourceCell";
    static NSString* const repositoryResourceCell = @"repositoryResourceCell";

    NSString* cellTypeId = nil;
    NSString* title = nil;
    NSString* subtitle = nil;
    if (tableView == self.searchDisplayController.searchResultsTableView)
    {
        id item_ = [_searchResults objectAtIndex:indexPath.row];

        if ([item_ isKindOfClass:[OAWorldRegion class]])
        {
            OAWorldRegion* item = (OAWorldRegion*)item_;

            cellTypeId = subregionCell;
            title = item.name;
            if (item.superregion != nil)
                subtitle = item.superregion.name;
        }
        else if ([item_ isKindOfClass:[OutdatedResourceItem class]])
        {
            OutdatedResourceItem* item = (OutdatedResourceItem*)item_;

            cellTypeId = outdatedResourceCell;
            title = item.title;
        }
        else if ([item_ isKindOfClass:[LocalResourceItem class]])
        {
            LocalResourceItem* item = (LocalResourceItem*)item_;

            cellTypeId = localResourceCell;
            title = item.title;
        }
        else if ([item_ isKindOfClass:[RepositoryResourceItem class]])
        {
            RepositoryResourceItem* item = (RepositoryResourceItem*)item_;

            cellTypeId = repositoryResourceCell;
            title = item.title;
        }
    }
    else
    {
        if (indexPath.section == _subregionsSection && _subregionsSection >= 0)
        {
            OAWorldRegion* worldRegion = [[self getSubregionItems] objectAtIndex:indexPath.row];

            cellTypeId = subregionCell;
            title = worldRegion.name;
            subtitle = nil;
        }
        else if (indexPath.section == _resourcesSection && _resourcesSection >= 0)
        {
            id item_ = [[self getResourceItems] objectAtIndex:indexPath.row];

            if ([item_ isKindOfClass:[OutdatedResourceItem class]])
            {
                OutdatedResourceItem* item = (OutdatedResourceItem*)item_;

                cellTypeId = outdatedResourceCell;
                title = item.title;
            }
            else if ([item_ isKindOfClass:[LocalResourceItem class]])
            {
                LocalResourceItem* item = (LocalResourceItem*)item_;

                cellTypeId = localResourceCell;
                title = item.title;
            }
            else if ([item_ isKindOfClass:[RepositoryResourceItem class]])
            {
                RepositoryResourceItem* item = (RepositoryResourceItem*)item_;
                
                cellTypeId = repositoryResourceCell;
                title = item.title;
            }
        }
    }

    // Obtain reusable cell or create one
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:cellTypeId];
    if (cell == nil)
    {
        if ([cellTypeId isEqualToString:outdatedResourceCell])
        {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                          reuseIdentifier:cellTypeId];
            UIImage* iconImage = [UIImage imageNamed:@"menu_item_update_icon.png"];
            cell.accessoryView = [[UIImageView alloc] initWithImage:[iconImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
        }
        else if ([cellTypeId isEqualToString:repositoryResourceCell])
        {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                          reuseIdentifier:cellTypeId];
            UIImage* iconImage = [UIImage imageNamed:@"menu_item_install_icon.png"];
            cell.accessoryView = [[UIImageView alloc] initWithImage:[iconImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
        }
        /*else if ([cellTypeId isEqualToString:downloadedItemCell])
        {
            FFCircularProgressView* progressView = [[FFCircularProgressView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 25.0f, 25.0f)];
            progressView.iconView = [[UIView alloc] init];
            [progressView startSpinProgressBackgroundLayer];
            cell = [[OATableViewCellWithClickableAccessoryView alloc] initWithStyle:UITableViewCellStyleDefault
                                                             andCustomAccessoryView:progressView
                                                                    reuseIdentifier:cellTypeId];
        }
        else
        {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                          reuseIdentifier:cellTypeId];
        }*/
    }

    // Try to allocate cell from own table, since it may be configured there
    if (cell == nil)
        cell = [self.tableView dequeueReusableCellWithIdentifier:cellTypeId];

    // Fill cell content
    cell.textLabel.text = title;
    if (cell.detailTextLabel != nil)
        cell.detailTextLabel.text = subtitle;
    /*if ([cellTypeId isEqualToString:downloadedItemCell])
    {
        DownloadedItem* downloadedItem = (DownloadedItem*)downloadItem;

        FFCircularProgressView* progressView = (FFCircularProgressView*)cell.accessoryView;
        float progressCompleted = downloadedItem.downloadTask.progressCompleted;
        if (progressCompleted >= 0.0f && downloadedItem.downloadTask.state == OADownloadTaskStateRunning)
        {
            [progressView stopSpinProgressBackgroundLayer];
            progressView.progress = progressCompleted;
        }
        else if (downloadedItem.downloadTask.state == OADownloadTaskStateFinished)
        {
            [progressView stopSpinProgressBackgroundLayer];
            progressView.progress = 1.0f;
        }
    }*/

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{
    id item = nil;
    if (tableView == self.searchDisplayController.searchResultsTableView)
        item = [_searchResults objectAtIndex:indexPath.row];
    else if (tableView == self.tableView)
    {
        if (indexPath.section == _subregionsSection && _subregionsSection >= 0)
            item = [[self getSubregionItems] objectAtIndex:indexPath.row];
        else if (indexPath.section == _resourcesSection && _resourcesSection >= 0)
            item = [[self getResourceItems] objectAtIndex:indexPath.row];
    }

    if (item == nil)
        return;

    [self onItemClicked:item];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    id item = nil;
    if (tableView == self.searchDisplayController.searchResultsTableView)
        item = [_searchResults objectAtIndex:indexPath.row];
    else if (tableView == self.tableView)
    {
        if (indexPath.section == _subregionsSection && _subregionsSection >= 0)
            item = [[self getSubregionItems] objectAtIndex:indexPath.row];
        else if (indexPath.section == _resourcesSection && _resourcesSection >= 0)
            item = [[self getResourceItems] objectAtIndex:indexPath.row];
    }

    if (item != nil)
        [self onItemClicked:item];

    [tableView deselectRowAtIndexPath:indexPath animated:true];
}

#pragma mark - UISearchDisplayDelegate

- (BOOL)searchDisplayController:(UISearchDisplayController *)controller shouldReloadTableForSearchScope:(NSInteger)searchOption
{
    _lastSearchScope = searchOption;
    [self performSearchForSearchString:_lastSearchString
                        andSearchScope:_lastSearchScope];

    return YES;
}

- (BOOL)searchDisplayController:(UISearchDisplayController *)controller shouldReloadTableForSearchString:(NSString *)searchString
{
    _lastSearchString = searchString;
    [self performSearchForSearchString:_lastSearchString
                        andSearchScope:_lastSearchScope];

    return YES;
}

- (void)searchDisplayControllerWillBeginSearch:(UISearchDisplayController *)controller
{
    [UIView animateWithDuration:0.3
                          delay:0.0
                        options:UIViewAnimationOptionCurveLinear
                     animations:^{
                         self.scopeControlContainerHeightConstraint.constant = 0.0f;
                         [self.scopeControlContainer.superview layoutIfNeeded];

                         self.scopeControlContainer.alpha = 0.0f;
                     } completion:^(BOOL finished) {
                         self.scopeControlContainer.userInteractionEnabled = NO;
                     }];
}

- (void)searchDisplayControllerWillEndSearch:(UISearchDisplayController *)controller
{
    //NOTE: This doesn't work as expected
    /*dispatch_async(dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.3
                              delay:0.0
                            options:UIViewAnimationOptionCurveLinear
                         animations:^{
                             self.scopeControlContainerHeightConstraint.constant = _originalScopeControlContainerHeight;
                             [self.scopeControlContainer.superview layoutIfNeeded];

                             self.scopeControlContainer.alpha = 1.0f;
                         } completion:^(BOOL finished) {
                             self.scopeControlContainer.userInteractionEnabled = YES;
                         }];
    });*/
}

- (void)searchDisplayControllerDidEndSearch:(UISearchDisplayController *)controller
{
    [UIView animateWithDuration:0.1
                          delay:0.0
                        options:UIViewAnimationOptionCurveLinear
                     animations:^{
                         self.scopeControlContainerHeightConstraint.constant = _originalScopeControlContainerHeight;
                         [self.scopeControlContainer.superview layoutIfNeeded];

                         self.scopeControlContainer.alpha = 1.0f;
                     } completion:^(BOOL finished) {
                         self.scopeControlContainer.userInteractionEnabled = YES;
                     }];
}

#pragma mark - Navigation

- (BOOL)shouldPerformSegueWithIdentifier:(NSString *)identifier sender:(id)sender
{
    if ([sender isKindOfClass:[UITableViewCell class]])
    {
        UITableViewCell* cell = (UITableViewCell*)sender;
        UITableView* tableView = [cell getTableView];
        NSIndexPath* cellPath = [tableView indexPathForCell:cell];

        if ([identifier isEqualToString:kOpenSubregionSegue])
        {
            OAWorldRegion* subregion = nil;
            if (tableView == _tableView && _subregionsSection >= 0)
                subregion = [[self getSubregionItems] objectAtIndex:cellPath.row];
            else if (tableView == self.searchDisplayController.searchResultsTableView)
                subregion = [_searchResults objectAtIndex:cellPath.row];

            return (subregion != nil);
        }
    }

    return NO;
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if (![sender isKindOfClass:[UITableViewCell class]])
        return;

    UITableViewCell* cell = (UITableViewCell*)sender;
    UITableView* tableView = [cell getTableView];
    NSIndexPath* cellPath = [tableView indexPathForCell:cell];

    if ([segue.identifier isEqualToString:kOpenSubregionSegue])
    {
        OAManageResourcesViewController* subregionViewController = [segue destinationViewController];

        OAWorldRegion* subregion = nil;
        if (tableView == _tableView && _subregionsSection >= 0)
            subregion = [[self getSubregionItems] objectAtIndex:cellPath.row];
        else if (tableView == self.searchDisplayController.searchResultsTableView)
            subregion = [_searchResults objectAtIndex:cellPath.row];

        [subregionViewController setupWithRegion:subregion
                             andWorldRegionItems:(_region == _app.worldRegion) ? _searchableSubregionItems : _searchableWorldwideRegionItems
                                        andScope:_currentScope];
    }
}

#pragma mark -

+ (OAWorldRegion*)findRegionOrAnySubregionOf:(OAWorldRegion*)region
                        thatContainsResource:(const QString&)resourceId
{
    const auto& downloadsIdPrefix = QString::fromNSString(region.downloadsIdPrefix);

    if (resourceId.startsWith(downloadsIdPrefix))
        return region;

    for (OAWorldRegion* subregion in region.subregions)
    {
        OAWorldRegion* match = [OAManageResourcesViewController findRegionOrAnySubregionOf:subregion
                                                                      thatContainsResource:resourceId];
        if (match)
            return match;
    }

    return nil;
}

@end
