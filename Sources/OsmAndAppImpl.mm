//
//  OsmAndAppImpl.m
//  OsmAnd
//
//  Created by Alexey Pelykh on 2/25/14.
//  Copyright (c) 2014 OsmAnd. All rights reserved.
//

#import "OsmAndAppImpl.h"

#import "OsmAndApp.h"

#include <algorithm>

#include <QList>

#include <OsmAndCore.h>
#include <OsmAndCore/Data/ObfFile.h>
#include <OsmAndCore/Data/ObfReader.h>
#include <OsmAndCore/Map/OnlineMapRasterTileProvidersDB.h>

@implementation OsmAndAppImpl
{
    std::shared_ptr<OsmAnd::ObfFile> _worldMiniBasemap;
}

@synthesize dataPath = _dataPath;
@synthesize documentsPath = _documentsPath;
@synthesize cachePath = _cachePath;

@synthesize installedOnlineTileProvidersDBPath = _installedOnlineTileProvidersDBPath;

@synthesize obfsCollection = _obfsCollection;
@synthesize mapStyles = _mapStyles;

- (id)init
{
    self = [super init];
    if (self) {
        [self ctor];
    }
    return self;
}

#define kAppData @"app_data"

- (void)ctor
{
    // Get default paths
    _dataPath = QDir(QString::fromNSString([NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject]));
    NSLog(@"Data path: %s", qPrintable(_dataPath.absolutePath()));
    _documentsPath = QDir(QString::fromNSString([NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]));
    NSLog(@"Documents path: %s", qPrintable(_documentsPath.absolutePath()));
    _cachePath = QDir(QString::fromNSString([NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject]));
    NSLog(@"Cache path: %s", qPrintable(_cachePath.absolutePath()));

    // First of all, initialize user defaults
    [[NSUserDefaults standardUserDefaults] registerDefaults:[self inflateInitialUserDefaults]];

    // Unpack app data
    _data = [NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] dataForKey:kAppData]];

    // Initialize online tile providers DB (if needed)
    _installedOnlineTileProvidersDBPath = _dataPath.absoluteFilePath(QLatin1String(kInstalledOnlineTileProvidersDBFilename));
    if(!QFile::exists(_installedOnlineTileProvidersDBPath))
    {
        NSLog(@"Copying default online tile providers DB to '%@'...", _installedOnlineTileProvidersDBPath.toNSString());
        if(!OsmAnd::OnlineMapRasterTileProvidersDB::createDefaultDB()->saveTo(_installedOnlineTileProvidersDBPath))
            NSLog(@"ERROR: Failed to copy default online tile providers DB to '%@'", _installedOnlineTileProvidersDBPath.toNSString());
    }

    // Get location of a shipped world mini-basemap and it's version stamp
    NSString* worldMiniBasemapFilename = [[NSBundle mainBundle] pathForResource:@"WorldMiniBasemap"
                                                        ofType:@"obf"
                                                   inDirectory:@"Shipped"];
    NSString* worldMiniBasemapStamp = [[NSBundle mainBundle] pathForResource:@"WorldMiniBasemap.obf"
                                                                      ofType:@"stamp"
                                                                 inDirectory:@"Shipped"];
    NSError* versionError = nil;
    NSString* worldMiniBasemapStampContents = [NSString stringWithContentsOfFile:worldMiniBasemapStamp
                                                                  encoding:NSASCIIStringEncoding
                                                                     error:&versionError];
    NSString* worldMiniBasemapVersion = [worldMiniBasemapStampContents stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSLog(@"Located shipped world mini-basemap (version %@) at %@", worldMiniBasemapVersion, worldMiniBasemapFilename);
    _worldMiniBasemap.reset(new OsmAnd::ObfFile(QString::fromNSString(worldMiniBasemapFilename)));

    [self initObfsCollection];
    [self initMapStyles];
    
    _mapModeObservable = [[OAObservable alloc] init];
    
    _locationServices = [[OALocationServices alloc] initWith:self];
    if(_locationServices.available && _locationServices.allowed)
        [_locationServices start];
}

- (void)initObfsCollection
{
    _obfsCollection.reset(new OsmAnd::ObfsCollection());
    
    // Set modifier to add world mini-basemap if there's no other basemap available
    _obfsCollection->setSourcesSetModifier([self](const OsmAnd::ObfsCollection& collection, QList< std::shared_ptr<OsmAnd::ObfReader> >& inOutSources)
    {
        const auto basemapPresent = std::any_of(inOutSources.cbegin(), inOutSources.cend(), [](const std::shared_ptr<OsmAnd::ObfReader>& obfReader)
        {
            return obfReader->obtainInfo()->isBasemap;
        });
        
        // If there's no basemap present, add mini-basemap
        if(!basemapPresent)
            inOutSources.push_back(std::shared_ptr<OsmAnd::ObfReader>(new OsmAnd::ObfReader(_worldMiniBasemap)));
    });
    
    // Register "Documents" directory (which is accessible from iTunes)
    _obfsCollection->registerDirectory(_documentsPath);
}

- (NSDictionary*)inflateInitialUserDefaults
{
    NSMutableDictionary* initialUserDefaults = [[NSMutableDictionary alloc] init];

    [initialUserDefaults setValue:[NSKeyedArchiver archivedDataWithRootObject:[OAAppData defaults]]
                            forKey:kAppData];

    return initialUserDefaults;
}

- (void)initMapStyles
{
    _mapStyles.reset(new OsmAnd::MapStyles());
}

@synthesize data = _data;

@synthesize locationServices = _locationServices;

@synthesize mapMode = _mapMode;
@synthesize mapModeObservable = _mapModeObservable;

- (void)setMapMode:(OAMapMode)mapMode
{
    if(_mapMode == mapMode)
        return;
    _mapMode = mapMode;
    [_mapModeObservable notifyEvent];
}

- (void)saveState
{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];

    // Save app data to user-defaults
    [userDefaults setObject:[NSKeyedArchiver archivedDataWithRootObject:_data]
                                              forKey:kAppData];
    [userDefaults synchronize];
}

@end
