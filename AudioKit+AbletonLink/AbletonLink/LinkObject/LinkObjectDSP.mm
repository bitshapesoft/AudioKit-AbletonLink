//
//  LinkObjectDSP.m
//  AudioKitTest
//
//  Created by Kevin Schlei on 1/20/21.
//

#include "SoundpipeDSPBase.h"
#include "ParameterRamper.h"
#include "soundpipe.h"
#include <vector>

#include "SharedLinkData.h"
#include <mach/mach_time.h>

enum LinkObjectParameter : AUParameterAddress {
    LinkObjectParameterFrequency
};

class LinkObjectDSP : public SoundpipeDSPBase {
private:
    
public:
    LinkObjectDSP() : SoundpipeDSPBase(/*inputBusCount*/0) {
        isStarted = false;
    }
    
    void setWavetable(const float* table, size_t length, int index) override {
        reset();
    }
    
    void init(int channelCount, double sampleRate) override {
        SoundpipeDSPBase::init(channelCount, sampleRate);
    }
    
    void deinit() override {
        SoundpipeDSPBase::deinit();
    }
    
    void reset() override {
        SoundpipeDSPBase::reset();
        if (!isInitialized) return;
    }
    
    /**
     Pull data from the main thread to the audio thread if lock can be
     obtained. Otherwise, just use the local copy of the data.
     */
    static void pullEngineData(LinkData* linkData, EngineData* output) {
        // Always reset the signaling members to their default state
        output->resetToBeatTime = INVALID_BEAT_TIME;
        output->proposeBpm = INVALID_BPM;
        output->requestStart = NO;
        output->requestStop = NO;

        // Attempt to grab the lock guarding the shared engine data but
        // don't block if we can't get it.
        if (os_unfair_lock_trylock(&sharedLock)) {
            // Copy non-signaling members to the local thread cache
            linkData->localEngineData.outputLatency = linkData->sharedEngineData.outputLatency;
            linkData->localEngineData.quantum = linkData->sharedEngineData.quantum;

            // Copy signaling members directly to the output and reset
            output->resetToBeatTime = linkData->sharedEngineData.resetToBeatTime;
            linkData->sharedEngineData.resetToBeatTime = INVALID_BEAT_TIME;

            output->requestStart = linkData->sharedEngineData.requestStart;
            linkData->sharedEngineData.requestStart = NO;

            output->requestStop = linkData->sharedEngineData.requestStop;
            linkData->sharedEngineData.requestStop = NO;

            output->proposeBpm = linkData->sharedEngineData.proposeBpm;
            linkData->sharedEngineData.proposeBpm = INVALID_BPM;

            os_unfair_lock_unlock(&sharedLock);
        }

        // Copy from the thread local copy to the output. This happens
        // whether or not we were able to grab the lock.
        output->outputLatency = linkData->localEngineData.outputLatency;
        output->quantum = linkData->localEngineData.quantum;
    }
    
    void process(AUAudioFrameCount frameCount, AUAudioFrameCount bufferOffset) override {
        // Get the reference to the global shared link data (from SharedLinkData.h)
        LinkData *linkData = &sharedLinkData;
                
        // Get a copy of the current link session state.
        const ABLLinkSessionStateRef sessionState = ABLLinkCaptureAudioSessionState(linkData->ablLink);
        
        // Pull the engine data from the shared Link data
        EngineData engineData;
        pullEngineData(linkData, &engineData);
        
        // The mHostTime member of the timestamp represents the time at
        // which the buffer is delivered to the audio hardware. The output
        // latency is the time from when the buffer is delivered to the
        // audio hardware to when the beginning of the buffer starts
        // reaching the output. We add those values to get the host time
        // at which the first sample of this buffer will reach the output.
        
        // Note: 'audioTimeStamp' was exposed from DSPBase as a protected
        // property. It is set in the DSPBase::processWithEvents function.
        // See the note at the bottom of this file.
        const UInt64 hostTimeAtBufferBegin = audioTimeStamp->mHostTime + UInt64(engineData.outputLatency);
        
        if (engineData.requestStart && !ABLLinkIsPlaying(sessionState)) {
            // Request starting playback at the beginning of this buffer.
            ABLLinkSetIsPlaying(sessionState, YES, hostTimeAtBufferBegin);
        }
        
        if (engineData.requestStop && ABLLinkIsPlaying(sessionState)) {
            // Request stopping playback at the beginning of this buffer.
            ABLLinkSetIsPlaying(sessionState, NO, hostTimeAtBufferBegin);
        }
        
        if (!linkData->isPlaying && ABLLinkIsPlaying(sessionState)) {
            // Reset the session state's beat timeline so that the requested
            // beat time corresponds to the time the transport will start playing.
            // The returned beat time is the actual beat time mapped to the time
            // playback will start, which therefore may be less than the requested
            // beat time by up to a quantum.
            ABLLinkRequestBeatAtStartPlayingTime(sessionState, 0.0, engineData.quantum);
            linkData->isPlaying = YES;
        }
        else if(linkData->isPlaying && !ABLLinkIsPlaying(sessionState)) {
            linkData->isPlaying = NO;
        }
        
        // Handle a tempo proposal
        if (engineData.proposeBpm != INVALID_BPM) {
            // Propose that the new tempo takes effect at the beginning of this buffer.
            ABLLinkSetTempo(sessionState, engineData.proposeBpm, hostTimeAtBufferBegin);
        }
        
        ABLLinkCommitAudioSessionState(linkData->ablLink, sessionState);
        
        // When playing, render the metronome sound
        if (linkData->isPlaying) {
            // Only render the metronome sound to the first channel. This
            // might help with source separate for timing analysis.
            
            // Metronome frequencies
            static const Float64 highTone = 900.0;
            static const Float64 lowTone = 600.0;
            
            // 100ms click duration
            static const Float64 clickDuration = 0.1;
            
            // The number of host ticks that elapse between samples
            const Float64 hostTicksPerSample = linkData->secondsToHostTime / sampleRate;
            
            for (int frameIndex = 0; frameIndex < frameCount; ++frameIndex) {
                int frameOffset = int(frameIndex + bufferOffset);
                
                for (int channel = 0; channel < channelCount; ++channel) {
                    float *out = (float *)outputBufferList->mBuffers[channel].mData + frameOffset;
                    *out = 0.0; //clear
                    
                    if (channel == 0) {
                        // Compute the host time for this sample.
                        const UInt64 hostTime = hostTimeAtBufferBegin + llround(frameIndex * hostTicksPerSample);
                        const UInt64 lastSampleHostTime = hostTime - llround(hostTicksPerSample);
                        // Only make sound for positive beat magnitudes. Negative beat
                        // magnitudes are count-in beats.
                        if (ABLLinkBeatAtTime(sessionState, hostTime, engineData.quantum) >= 0.) {
                            // If the phase wraps around between the last sample and the
                            // current one with respect to a 1 beat quantum, then a click
                            // should occur.
                            double samplePhase = ABLLinkPhaseAtTime(sessionState, hostTime, 1.0 / 4.0);
                            double prevSamplePhase = ABLLinkPhaseAtTime(sessionState, lastSampleHostTime, 1.0 / 4.0);
                            if (samplePhase < prevSamplePhase) {
                                linkData->timeAtLastClick = hostTime;
                            }
                            
                            const Float64 secondsAfterClick = (hostTime - linkData->timeAtLastClick) / linkData->secondsToHostTime;
                            
                            // If we're within the click duration of the last beat, render
                            // the click tone into this sample
                            Float64 amplitude = 0.0;
                            if (secondsAfterClick < clickDuration) {
                                // Linear fade for clickDuration
                                Float64 fade = 1.0 - secondsAfterClick / clickDuration;

                                // If the phase of the last beat with respect to the current
                                // quantum was zero, then it was at a quantum boundary and we
                                // want to use the high tone. For other beats within the
                                // quantum, use the low tone.
                                UInt32 quantumBeat = UInt32(floor(ABLLinkPhaseAtTime(sessionState, hostTime, engineData.quantum)));
                                bool downbeat = (quantumBeat == 0);
                                const Float64 freq = (downbeat) ? highTone : lowTone;

                                // Simple cosine synth
                                amplitude = cos(2 * M_PI * secondsAfterClick * freq) * fade;
                                
                                *out = amplitude;
                            }
                        }
                    }
                }
            }
        }
        else {
            //clear buffer
            for (int channel = 0; channel < channelCount; ++channel) {
                if (channel == 0) {
                    memset(outputBufferList->mBuffers[channel].mData, 0, frameCount * sizeof(float));
                }
            }
        }
    }
};

AK_REGISTER_DSP(LinkObjectDSP)

//===================================================================================
//MARK: Exposing AudioTimeStamp
/** (Note: to alter a file inside of a Swift Package, you need to copy it locally on your
 drive, alter that version, then overwrite the original file.)

 //----------------------------------------------------------------------------------
 In DSPBase.h, add this under the protected ivars:
 
 class DSPBase {
     ...
 protected:
     // Host time stamp when the buffer is delivered to the output
     AudioTimeStamp const *audioTimeStamp;
     ...
 
 //----------------------------------------------------------------------------------
 In DSPBase.mm, add this in the processWithEvents(...) function:
 
 void DSPBase::processWithEvents(AudioTimeStamp const *timestamp, AUAudioFrameCount frameCount,
                                   AURenderEvent const *events)
 {
     audioTimeStamp = timestamp;
     ...
 */
//===================================================================================
