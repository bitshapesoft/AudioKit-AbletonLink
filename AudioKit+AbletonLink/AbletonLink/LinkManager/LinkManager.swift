//
//  ABLLinkManager.swift
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors.
//  Copyright © 2017 AudioKit. All rights reserved.
//

import AVFoundation

//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
//MARK: ABLLinkManagerListenerType
//_______________________________________________________________________________________

public typealias ABLLinkManagerTempoCallback = (_ bpm: Double, _ quantum: Double) -> Void
public typealias ABLLinkManagerActivationCallback = (_ isEnabled: Bool) -> Void
public typealias ABLLinkManagerConnectionCallback = (_ isConnected: Bool) -> Void

public enum ABLLinkManagerListenerType {
    case tempo(ABLLinkManagerTempoCallback)
    case activation(ABLLinkManagerActivationCallback)
    case connection(ABLLinkManagerConnectionCallback)
}

//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
//MARK: ABLLinkManagerListener
//_______________________________________________________________________________________

public struct ABLLinkManagerListener: Equatable {
    public private(set) var id: String
    public private(set) var type: ABLLinkManagerListenerType
    
    public init(type: ABLLinkManagerListenerType) {
        self.id = UUID().uuidString
        self.type = type
    }
    
    //===================================================================================
    //MARK: Equatable
    //===================================================================================
    
    public static func ==(lhs: ABLLinkManagerListener, rhs: ABLLinkManagerListener) -> Bool {
        return lhs.id == rhs.id
    }
}

//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
//MARK: Link Manager
//_______________________________________________________________________________________

/**
 Use the shared class object to gather updated information about the Link session. Set data
 via the convenience properties, and then call the update() method to notify any
 listeners.
 */

public let INVALID_BEAT_TIME: Double = Double.leastNormalMagnitude
public let INVALID_BPM: Double = Double.leastNormalMagnitude
public let QUANTUM_DEFAULT: Float64 = 4

public class ABLLinkManager: NSObject {
    
    //===================================================================================
    //MARK: Public Properties
    //===================================================================================
    
    public static let shared = ABLLinkManager()
    
    public var isDebugging: Bool = false
    
    //===================================================================================
    //MARK: Private Properties
    //===================================================================================
    
    private var lock = os_unfair_lock()
    
    private var listeners = [ABLLinkManagerListener]()
    
    //===================================================================================
    //MARK: Lifecycle
    //===================================================================================
    
    private override init() {
        super.init()
    }
    
    deinit {
        // Deletes Link (don't have multiples of this). Do this during app shutdown
        ABLLinkDelete(sharedLinkData.ablLink)
    }
    
    //===================================================================================
    //MARK: Public API
    //===================================================================================
    
    /// Reference of Link itself.
    public var linkRef: ABLLinkRef? {
        return sharedLinkData.ablLink
    }
    
    /// Detemines if Link is connected or not.
    public var isConnected: Bool {
        guard let ref = sharedLinkData.ablLink else { return false }
        return ABLLinkIsConnected(ref)
    }
    
    /// Determines if Link is enabled or not.
    public var isEnabled: Bool {
        guard let linkRef = linkRef else { return false }
        return ABLLinkIsEnabled(linkRef)
    }
    
    /// Detemines if Link is playing or not.
    public var isPlaying: Bool {
        get {
            guard let linkRef = linkRef,
                  let sessionState = ABLLinkCaptureAppSessionState(linkRef)
            else { return false }
            return ABLLinkIsPlaying(sessionState)
        } set {
            os_unfair_lock_lock(&lock)
            if newValue { // isPlaying
                sharedLinkData.sharedEngineData.requestStart = ObjCBool(true)
            } else {
                sharedLinkData.sharedEngineData.requestStop = ObjCBool(true)
            }
            os_unfair_lock_unlock(&lock)
        }
    }
    
    /// Beats per minute.
    public var bpm: Float64 {
        get {
            guard let linkRef = linkRef else { return INVALID_BPM }
            return ABLLinkGetTempo(ABLLinkCaptureAppSessionState(linkRef))
        } set {
            print("ABL: Set Bpm to", newValue)
            os_unfair_lock_lock(&lock)
            sharedLinkData.sharedEngineData.proposeBpm = newValue
            os_unfair_lock_unlock(&lock)
        }
    }
    
    /// Current beat.
    public var beatTime: Float64 {
        guard let linkRef = linkRef else {
            print("ABL: LinkData invalid when trying to get beat. Returning 0.")
            return 0
        }
        
        return ABLLinkBeatAtTime(
            ABLLinkCaptureAppSessionState(linkRef),
            mach_absolute_time(),
            quantum)
    }
    
    /// Current quantum.
    public var quantum: Float64 {
        get {
            return sharedLinkData.sharedEngineData.quantum
        } set {
            os_unfair_lock_lock(&lock)
            sharedLinkData.sharedEngineData.quantum = newValue
            os_unfair_lock_unlock(&lock)
        }
    }
    
    /// Returns Link settings view controller initilized with Link reference.
    public var settingsViewController: ABLLinkSettingsViewController? {
        return ABLLinkSettingsViewController.instance(sharedLinkData.ablLink)
    }
    
    /// Initilizes Link with tempo and quantum.
    ///
    /// - Parameters:
    ///   - bpm: Tempo.
    ///   - quantum: Quantum.
    public func setup(bpm: Double, quantum: Float64) {
        print("ABL: Init")
        
        var timeInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timeInfo)
        
        // Create Link (don't have multiple instances)
        // Always initialized with a tempo, even if just a default
        // Use app tempo unless there is an existing tempo from the network
        sharedLinkData.ablLink = ABLLinkNew(bpm)
        sharedLinkData.sampleRate = AVAudioSession.sharedInstance().sampleRate
        sharedLinkData.secondsToHostTime = (1.0e9 * Float64(timeInfo.denom)) / Float64(timeInfo.numer)
        sharedLinkData.sharedEngineData.outputLatency = (UInt32)(sharedLinkData.secondsToHostTime * AVAudioSession.sharedInstance().outputLatency)
        sharedLinkData.sharedEngineData.resetToBeatTime = INVALID_BEAT_TIME
        sharedLinkData.sharedEngineData.proposeBpm = INVALID_BPM
        sharedLinkData.sharedEngineData.requestStart = false
        sharedLinkData.sharedEngineData.requestStop = false
        sharedLinkData.sharedEngineData.quantum = quantum
        sharedLinkData.localEngineData = sharedLinkData.sharedEngineData
        sharedLinkData.timeAtLastClick = 0
        
        addListeners()
    }
    
    //===================================================================================
    //MARK: Listeners
    //===================================================================================
    
    /// Add listeners to subscribe changes. Don't forget to keep a reference of your listener and remove it after you're done.
    ///
    /// - Parameter type: Listener type with callback.
    /// - Returns: Listener reference that you can unsubscribe later.
    @discardableResult public func add(listener type: ABLLinkManagerListenerType) -> ABLLinkManagerListener {
        let listener = ABLLinkManagerListener(type: type)
        listeners.append(listener)
        return listener
    }
    
    /// Unsubscribes your listener after you're done.
    ///
    /// - Parameter listener: Listener you want to remove.
    /// - Returns: Returns result of the operation.
    @discardableResult public func remove(listener: ABLLinkManagerListener) -> Bool {
        guard let index = listeners.firstIndex(of: listener) else { return false }
        listeners.remove(at: index)
        return true
    }
    
    /// Removes all listeners.
    public func removeAllListeners() {
        listeners = []
    }
    
    //===================================================================================
    //MARK: Update
    //===================================================================================
    
    public func printStuff() {
        print("ABL: Proposed BPM = ", sharedLinkData.sharedEngineData.proposeBpm)
    }
    
    //===================================================================================
    //MARK: Adding / Removing Listeners
    //===================================================================================
    
    private func addListeners() {
        // Route change
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance())
        
        guard let ref = sharedLinkData.ablLink else {
            print("ABL: Error getting linkRef when adding listeners")
            return
        }
        
        // Void pointer to self for C callbacks below
        // http://stackoverflow.com/questions/33260808/swift-proper-use-of-cfnotificationcenteraddobserver-w-callback
        let selfAsURP = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let selfAsUMRP = UnsafeMutableRawPointer(mutating: selfAsURP)
        
        // Add listener to detect tempo changes from other devices
        
        ABLLinkSetSessionTempoCallback(ref, { sessionTempo, context in
            if let context = context {
                let localSelf = Unmanaged<ABLLinkManager>.fromOpaque(context).takeUnretainedValue()
                let localSelfAsUMRP = UnsafeMutableRawPointer(mutating: context)
                localSelf.onSessionTempoChanged(bpm: sessionTempo, context: localSelfAsUMRP)
            }
        }, selfAsUMRP)
        
        ABLLinkSetIsEnabledCallback(ref, { isEnabled, context in
            if let context = context {
                let localSelf = Unmanaged<ABLLinkManager>.fromOpaque(context).takeUnretainedValue()
                let localSelfAsUMRP = UnsafeMutableRawPointer(mutating: context)
                localSelf.onLinkEnabled(isEnabled: isEnabled, context: localSelfAsUMRP)
            }
        }, selfAsUMRP)
        
        ABLLinkSetIsConnectedCallback(ref, { isConnected, context in
            if let context = context {
                let localSelf = Unmanaged<ABLLinkManager>.fromOpaque(context).takeUnretainedValue()
                let localSelfAsUMRP = UnsafeMutableRawPointer(mutating: context)
                localSelf.onConnectionStatusChanged(isConnected: isConnected, context: localSelfAsUMRP)
            }
        }, selfAsUMRP)
    }
    
    // Route change
    @objc internal func handleRouteChange() {
        let outputLatency: UInt32 = UInt32(sharedLinkData.secondsToHostTime * AVAudioSession.sharedInstance().outputLatency)
        os_unfair_lock_lock(&lock)
        sharedLinkData.sharedEngineData.outputLatency = outputLatency
        os_unfair_lock_unlock(&lock)
        print("ABL: Route change")
    }
    
    // Tempo changes from other Link devices
    private func onSessionTempoChanged(bpm: Double, context: Optional<UnsafeMutableRawPointer>) {
        print("ABL: onSessionTempoChanged")
        //update local var
        self.bpm = bpm
        print("ABL: curr bpm", bpm)
        
        // Inform listeners
        for listener in listeners {
            if case .tempo(let callback) = listener.type {
                callback(bpm, quantum)
            }
        }
    }
    
    // On Link enabled
    private func onLinkEnabled(isEnabled: Bool, context: Optional<UnsafeMutableRawPointer>) {
        print("ABL: Link is", isEnabled)
        
        // Inform listeners
        for listener in listeners {
            if case .activation(let callback) = listener.type {
                callback(isEnabled)
            }
        }
    }
    
    // Connection Status from ther devices changed
    private func onConnectionStatusChanged(isConnected: Bool, context: Optional<UnsafeMutableRawPointer>) -> () {
        print("ABL: onConnectionStatusChanged: isConnected = ", isConnected)
        
        // Inform listeners
        for listener in listeners {
            if case .connection(let callback) = listener.type {
                callback(isConnected)
            }
        }
    }
}

//class AKLinkButton: SynthButton {
//
//    #if ABLETON_ENABLED_1
//    private var realSuperView: UIView?
//    private var controller: UIViewController?
//    private var linkViewController: ABLLinkSettingsViewController?
//
//    /// Use this when your button's superview is not the entire screen, or when you prefer
//    /// the aesthetics of a centered popup window to one with an arrow pointing to your button
//    public func centerPopupIn(view: UIView) {
//        realSuperView = view
//    }
//
//    /// Handle touches
//    override public func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
//        super.touchesEnded(touches, with: event)
//
//        let linkViewController = ABLLinkSettingsViewController.instance(ABLLinkManager.shared.ablLink)
//        let navController = UINavigationController(rootViewController: linkViewController!)
//
//        navController.modalPresentationStyle = .popover
//
//        let popC = navController.popoverPresentationController
//        let centerPopup = realSuperView != nil
//        let displayView = realSuperView ?? self.superview
//
//        popC?.permittedArrowDirections = centerPopup ? [] : .any
//        popC?.sourceRect = centerPopup ? CGRect(x: displayView!.bounds.midX,
//                                                y: displayView!.bounds.midY,
//                                                width: 0,
//                                                height: 0) : self.frame
//
//        controller = displayView!.next as? UIViewController
//        controller?.present(navController, animated: true, completion: nil)
//
//        popC?.sourceView = controller?.view
//        linkViewController?.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
//                                                                                target: self,
//                                                                                action: #selector(doneAction))
//
//    }
//
//    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
//        // Do nothing to avoid changing selected state
//    }
//
//    @objc public func doneAction() {
//        controller?.dismiss(animated: true, completion: nil)
//        value = ABLLinkManager.shared.isEnabled ? 1 : 0
//    }
//
//}
