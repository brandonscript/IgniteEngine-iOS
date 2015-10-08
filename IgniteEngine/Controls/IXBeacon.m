//
//  IXBeacon.m
//  IgniteEngineStarterKit
//
//  Created by Robert Walsh on 10/7/15.
//  Copyright © 2015 Apigee. All rights reserved.
//

#import "IXBeacon.h"
#import "IXLocationManager.h"
#import "NSString+IXAdditions.h"
#import <KontaktSDK/KontaktSDK.h>

@import CoreLocation;

// IXBeacon Attributes
IX_STATIC_CONST_STRING kIXRegionUUIDs = @"regionUUIDs";
IX_STATIC_CONST_STRING kIXDistanceFilter = @"distanceFilter";

// IXBeacon ReadOnly Attributes
IX_STATIC_CONST_STRING kIXCanMonitorBeacons = @"canMonitorBeacons";
IX_STATIC_CONST_STRING kIXTripData = @"tripData";

// IXBeacon Functions
IX_STATIC_CONST_STRING kIXStart = @"stop";
IX_STATIC_CONST_STRING kIXStop = @"start";

// IXBeacon Events
IX_STATIC_CONST_STRING kIXEnteredBeaconRegion = @"enteredBeaconRegion";
IX_STATIC_CONST_STRING kIXExitedBeaconRegion = @"exitedBeaconRegion";

// Non attribute constants
IX_STATIC_CONST_STRING kIXWayPoints = @"waypoints";

@interface IXLocationManager ()

@property (nonatomic,strong) CLLocationManager* locationManager;

@end

@interface IXBeacon () <KTKLocationManagerDelegate,IXLocationManagerDelegate>

@property (strong,nonatomic) KTKLocationManager *locationManager;
@property (strong,nonatomic) IXLocationManager* locationTrackerManager;
@property (strong,nonatomic) NSArray *regionsToMonitor;

@property (nonatomic, strong) NSMutableArray *waypoints;
@property (nonatomic, strong) NSDictionary *start;
@property (nonatomic, strong) NSDictionary *stop;
@property (nonatomic, strong) NSMutableDictionary *tripData;
@property (nonatomic, assign) UIBackgroundTaskIdentifier locationTrackingTask;

@end

@implementation IXBeacon

-(void)dealloc
{
    [self.locationManager stopMonitoringBeacons];
    self.locationManager.delegate = nil;
    [self.locationTrackerManager stopTrackingLocation];
    self.locationTrackerManager.delegate = nil;
}

-(void)buildView
{
    self.locationManager = [[KTKLocationManager alloc]init];
    self.locationManager.delegate = self;

    self.locationTrackerManager = [[IXLocationManager alloc] init];
    self.locationTrackerManager.delegate = self;

    [self.locationTrackerManager.locationManager setDesiredAccuracy:kCLLocationAccuracyBestForNavigation];
    [self.locationTrackerManager requestAccessToLocation];
}

-(void)applySettings
{
    [super applySettings];

    [self.locationTrackerManager.locationManager setDistanceFilter:[self.attributeContainer getFloatValueForAttribute:kIXDistanceFilter defaultValue:20.0f]];

    NSMutableArray* regionsToMonitor = [NSMutableArray array];
    NSArray* regionUUIDs = [self.attributeContainer getCommaSeparatedArrayOfValuesForAttribute:kIXRegionUUIDs defaultValue:nil];
    for( NSString* regionUUID in regionUUIDs ) {
        [regionsToMonitor addObject:[[KTKRegion alloc] initWithUUID:regionUUID]];
    }
    self.regionsToMonitor = regionsToMonitor;
}

-(void)applyFunction:(NSString *)functionName withParameters:(IXAttributeContainer *)parameterContainer
{
    if( [functionName isEqualToString:kIXStart] ) {
        if( [KTKLocationManager canMonitorBeacons] ) {
            [self.locationManager setRegions:self.regionsToMonitor];
            [self.locationManager startMonitoringBeacons];
        } else {
            NSLog(@"ERROR: Cannot monitor beacons.");
        }
    } else if( [functionName isEqualToString:kIXStop] ) {
        [self.locationManager stopMonitoringBeacons];
    } else {
        [super applyFunction:functionName withParameters:parameterContainer];
    }
}

-(NSString *)getReadOnlyPropertyValue:(NSString *)propertyName
{
    NSString* returnValue = nil;
    if( [propertyName isEqualToString:kIXCanMonitorBeacons] ) {
        returnValue = [NSString ix_stringFromBOOL:[KTKLocationManager canMonitorBeacons]];
    } else if( [propertyName isEqualToString:kIXTripData] ) {
        if( self.tripData != nil && [NSJSONSerialization isValidJSONObject:self.tripData] ) {
            NSError* err;
            NSData* jsonData = [NSJSONSerialization dataWithJSONObject:self.tripData options:0 error:&err];
            returnValue = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        }
    }
    else {
        returnValue = [super getReadOnlyPropertyValue:propertyName];
    }
    return returnValue;
}

- (void)locationManager:(KTKLocationManager *)locationManager didChangeState:(KTKLocationManagerState)state withError:(NSError *)error
{
    if (state == KTKLocationManagerStateFailed)
    {
        NSLog(@"Something went wrong with your Location Services settings. Check OS settings.");
    }
}

-(void)locationManager:(KTKLocationManager *)locationManager didEnterRegion:(KTKRegion *)region
{
    self.start = nil;
    self.stop = nil;
    self.waypoints = nil;
    self.tripData = nil;

    [self.locationTrackerManager.locationManager startMonitoringSignificantLocationChanges];
    [self.locationTrackerManager beginLocationTracking];

    [self.actionContainer executeActionsForEventNamed:kIXEnteredBeaconRegion];
}

-(void)locationManager:(KTKLocationManager *)locationManager didExitRegion:(KTKRegion *)region
{
    [self.locationTrackerManager.locationManager stopMonitoringSignificantLocationChanges];
    [self.locationTrackerManager stopTrackingLocation];

    if (self.waypoints != nil) {
        [self.waypoints removeLastObject];
    }

    if (self.tripData == nil) {
        self.tripData = [[NSMutableDictionary alloc]init];
    }
    if (self.start!=nil) {
        [self.tripData setObject:self.start forKey:kIXStart];
    }
    if (self.waypoints!=nil) {
        [self.tripData setObject:self.waypoints forKey:kIXWayPoints];
    }
    if (self.stop!=nil) {
        [self.tripData setObject:self.stop forKey:kIXStop];
    }
    
    [self.actionContainer executeActionsForEventNamed:kIXExitedBeaconRegion];
}

-(void)locationManagerAuthStatusChanged:(CLAuthorizationStatus)status;
{
    // Do stuff maybe?
}

-(void)locationManagerDidUpdateLocation:(CLLocation*)location
{
    self.locationTrackingTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        [[UIApplication sharedApplication] endBackgroundTask:self.locationTrackingTask];
        self.locationTrackingTask = UIBackgroundTaskInvalid;
    }];

    NSNumber *timestamp = [NSNumber numberWithDouble:[location.timestamp timeIntervalSince1970]*1000];

    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    [formatter setRoundingMode:NSNumberFormatterRoundHalfUp];
    [formatter setMaximumFractionDigits:0];

    NSDictionary *locationDict = @{@"lat":[NSNumber numberWithDouble:location.coordinate.latitude],
                                   @"lng":[NSNumber numberWithDouble:location.coordinate.longitude],
                                   @"timestamp":[formatter stringFromNumber:timestamp]};

    if (self.start == nil) {
        self.start = locationDict;
    } else {
        [self.waypoints addObject:locationDict];
    }
    self.stop = locationDict;
}

- (void)locationManager:(KTKLocationManager *)locationManager didRangeBeacons:(NSArray *)beacons
{
    NSLog(@"Ranged beacons count: %lu", (unsigned long)[beacons count]);
    [beacons enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        CLBeacon* beacon = (CLBeacon*)obj;
        NSLog(@"%d - major %d minor %d strength %d accuracy %f",idx,[beacon.major intValue],[beacon.minor intValue],beacon.rssi,beacon.accuracy);
    }];
}

@end
