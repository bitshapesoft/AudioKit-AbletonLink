//
//  LinkEngine.hpp
//  AudioKitTest
//
//  Created by Kevin Schlei on 1/23/21.
//

#ifndef LinkEngine_hpp
#define LinkEngine_hpp

#include <AVFoundation/AVFoundation.h>
#include <os/lock.h>

#include "ABLLink.h"

#define INVALID_BEAT_TIME DBL_MIN
#define INVALID_BPM DBL_MIN

//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
//MARK: EngineData
//_______________________________________________________________________________________

/** Structure that stores engine-related data that can be changed from the main thread. */
typedef struct {
  UInt32 outputLatency; // Hardware output latency in HostTime
  Float64 resetToBeatTime;
  BOOL requestStart;
  BOOL requestStop;
  Float64 proposeBpm;
  Float64 quantum;
} EngineData;

//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
//MARK: LinkData
//_______________________________________________________________________________________

/** Structure that stores all data needed by the audio callback. */
typedef struct {
    ABLLinkRef ablLink;
    // Shared between threads. Only write when engine not running.
    Float64 sampleRate;
    // Shared between threads. Only write when engine not running.
    Float64 secondsToHostTime;
    // Shared between threads. Written by the main thread and only
    // read by the audio thread when doing so will not block.
    EngineData sharedEngineData;
    // Copy of sharedEngineData owned by audio thread.
    EngineData localEngineData;
    // Owned by audio thread
    UInt64 timeAtLastClick;
    // Owned by audio thread
    BOOL isPlaying;
} LinkData;

//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
//MARK: Shared Link Data
//_______________________________________________________________________________________

/** This data is referenced in both the AudioKit LinkObject node, and the LinkObjectDSP. */
extern LinkData sharedLinkData;

//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
//MARK: Shared Lock
//_______________________________________________________________________________________

/** The lock used by the audio thread during the pullEngineData function. */
extern struct os_unfair_lock_s sharedLock;

#endif /* LinkEngine_hpp */
