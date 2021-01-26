//
//  LinkEngine.cpp
//  AudioKitTest
//
//  Created by Kevin Schlei on 1/24/21.
//

#include "SharedLinkData.h"

LinkData sharedLinkData;
os_unfair_lock_s sharedLock = OS_UNFAIR_LOCK_INIT;
