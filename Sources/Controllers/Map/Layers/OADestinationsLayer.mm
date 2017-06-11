//
//  OADestinationsLayer.m
//  OsmAnd
//
//  Created by Alexey Kulish on 09/06/2017.
//  Copyright © 2017 OsmAnd. All rights reserved.
//

#import "OADestinationsLayer.h"
#import "OANativeUtilities.h"
#import "OAMapViewController.h"
#import "OAMapRendererView.h"
#import "OAUtilities.h"
#import "OADestination.h"
#import "OAAutoObserverProxy.h"

#include <OsmAndCore/Utilities.h>
#include <OsmAndCore/Map/MapMarker.h>
#include <OsmAndCore/Map/MapMarkerBuilder.h>
#include <OsmAndCore/Map/FavoriteLocationsPresenter.h>


@implementation OADestinationsLayer
{
    std::shared_ptr<OsmAnd::MapMarkersCollection> _destinationsMarkersCollection;

    OAAutoObserverProxy* _destinationAddObserver;
    OAAutoObserverProxy* _destinationRemoveObserver;
    OAAutoObserverProxy* _destinationShowObserver;
    OAAutoObserverProxy* _destinationHideObserver;
}

+ (NSString *) getLayerId
{
    return kDestinationsLayerId;
}

- (void) initLayer
{
    [super initLayer];
    
    _destinationAddObserver = [[OAAutoObserverProxy alloc] initWith:self
                                                           withHandler:@selector(onDestinationAdded:withKey:)
                                                            andObserve:self.app.data.destinationAddObservable];

    _destinationRemoveObserver = [[OAAutoObserverProxy alloc] initWith:self
                                                           withHandler:@selector(onDestinationRemoved:withKey:)
                                                            andObserve:self.app.data.destinationRemoveObservable];

    _destinationShowObserver = [[OAAutoObserverProxy alloc] initWith:self
                                                         withHandler:@selector(onDestinationShow:withKey:)
                                                          andObserve:self.app.data.destinationShowObservable];
    _destinationHideObserver = [[OAAutoObserverProxy alloc] initWith:self
                                                         withHandler:@selector(onDestinationHide:withKey:)
                                                          andObserve:self.app.data.destinationHideObservable];

    [self refreshDestinationsMarkersCollection];
    
    [self.app.data.mapLayersConfiguration setLayer:[self.class getLayerId] Visibility:YES];
}

- (void) deinitLayer
{
    [super deinitLayer];
    
    if (_destinationShowObserver)
    {
        [_destinationShowObserver detach];
        _destinationShowObserver = nil;
    }
    if (_destinationHideObserver)
    {
        [_destinationHideObserver detach];
        _destinationHideObserver = nil;
    }
    if (_destinationAddObserver)
    {
        [_destinationAddObserver detach];
        _destinationAddObserver = nil;
    }
    if (_destinationRemoveObserver)
    {
        [_destinationRemoveObserver detach];
        _destinationRemoveObserver = nil;
    }
}

- (std::shared_ptr<OsmAnd::MapMarkersCollection>) getDestinationsMarkersCollection
{
    return _destinationsMarkersCollection;
}

- (void) refreshDestinationsMarkersCollection
{
    _destinationsMarkersCollection.reset(new OsmAnd::MapMarkersCollection());

    for (OADestination *destination in self.app.data.destinations)
        if (!destination.routePoint && !destination.hidden)
            [self addDestinationPin:destination.markerResourceName color:destination.color latitude:destination.latitude longitude:destination.longitude];

}

- (void)addDestinationPin:(NSString *)markerResourceName color:(UIColor *)color latitude:(double)latitude longitude:(double)longitude
{
    CGFloat r,g,b,a;
    [color getRed:&r green:&g blue:&b alpha:&a];
    OsmAnd::FColorRGB col(r, g, b);
    
    const OsmAnd::LatLon latLon(latitude, longitude);
    
    OsmAnd::MapMarkerBuilder()
    .setIsAccuracyCircleSupported(false)
    .setBaseOrder(-207000)
    .setIsHidden(false)
    .setPinIcon([OANativeUtilities skBitmapFromPngResource:markerResourceName])
    .setPosition(OsmAnd::Utilities::convertLatLonTo31(latLon))
    .setPinIconVerticalAlignment(OsmAnd::MapMarker::Top)
    .setPinIconHorisontalAlignment(OsmAnd::MapMarker::CenterHorizontal)
    .setAccuracyCircleBaseColor(col)
    .buildAndAddToCollection(_destinationsMarkersCollection);
}

- (void)removeDestinationPin:(double)latitude longitude:(double)longitude;
{
    for (const auto &marker : _destinationsMarkersCollection->getMarkers())
    {
        OsmAnd::LatLon latLon = OsmAnd::Utilities::convert31ToLatLon(marker->getPosition());
        if ([OAUtilities doublesEqualUpToDigits:5 source:latLon.latitude destination:latitude] &&
            [OAUtilities doublesEqualUpToDigits:5 source:latLon.longitude destination:longitude])
        {
            _destinationsMarkersCollection->removeMarker(marker);
            break;
        }
    }
}


- (void) show
{
    [self.mapViewController runWithRenderSync:^{
        [self.mapView addKeyedSymbolsProvider:_destinationsMarkersCollection];
    }];
}

- (void) hide
{
    [self.mapViewController runWithRenderSync:^{
        [self.mapView removeKeyedSymbolsProvider:_destinationsMarkersCollection];
    }];
}

- (void)onDestinationAdded:(id)observable withKey:(id)key
{
    OADestination *destination = key;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self addDestinationPin:destination.markerResourceName color:destination.color latitude:destination.latitude longitude:destination.longitude];
    });
}

- (void)onDestinationRemoved:(id)observable withKey:(id)key
{
    OADestination *destination = key;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self removeDestinationPin:destination.latitude longitude:destination.longitude];
    });
}


- (void)onDestinationShow:(id)observer withKey:(id)key
{
    OADestination *destination = key;
    
    if (destination)
    {
        BOOL exists = NO;
        for (const auto &marker : _destinationsMarkersCollection->getMarkers())
        {
            OsmAnd::LatLon latLon = OsmAnd::Utilities::convert31ToLatLon(marker->getPosition());
            if ([OAUtilities doublesEqualUpToDigits:5 source:latLon.latitude destination:destination.latitude] &&
                [OAUtilities doublesEqualUpToDigits:5 source:latLon.longitude destination:destination.longitude])
            {
                exists = YES;
                break;
            }
        }
        
        if (!exists)
            [self addDestinationPin:destination.markerResourceName color:destination.color latitude:destination.latitude longitude:destination.longitude];
    }
}

- (void)onDestinationHide:(id)observer withKey:(id)key
{
    OADestination *destination = key;
    
    if (destination)
    {
        for (const auto &marker : _destinationsMarkersCollection->getMarkers())
        {
            OsmAnd::LatLon latLon = OsmAnd::Utilities::convert31ToLatLon(marker->getPosition());
            if ([OAUtilities doublesEqualUpToDigits:5 source:latLon.latitude destination:destination.latitude] &&
                [OAUtilities doublesEqualUpToDigits:5 source:latLon.longitude destination:destination.longitude])
            {
                _destinationsMarkersCollection->removeMarker(marker);
                break;
            }
        }
    }
}

@end
