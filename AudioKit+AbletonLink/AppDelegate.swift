//
//  AppDelegate.swift
//  AudioKit+AbletonLink
//
//  Created by Kevin Schlei on 1/26/21.
//

import UIKit
import AudioKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    //===================================================================================
    //MARK: Public Properties
    //===================================================================================
    
    let engine = AudioKit.AudioEngine()

    //===================================================================================
    //MARK: Lifecycle
    //===================================================================================
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        #if os(iOS)
        do {
            Settings.bufferLength = .veryLong
            try AVAudioSession.sharedInstance().setPreferredIOBufferDuration(Settings.bufferLength.duration)
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord,
                                                            options: [.defaultToSpeaker, .mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch let err {
            print(err)
        }
        #endif
        
        // Set up the LinkManager (from AudioKitSynthOne)
        ABLLinkManager.shared.setup(bpm: 120.0, quantum: QUANTUM_DEFAULT)
        ABLLinkManager.shared.bpm = 105
        ABLLinkManager.shared.isPlaying = true
        
        // Create an AudioKit LinkObject, which will output an audible click
        let linkObj = LinkObject()
        linkObj.start()
        
        // Attach the LinkObject to the output
        engine.output = linkObj
        
        // Start the AudioKit engine
        do {
            try engine.start()
        } catch {
            print("error starting engine \(error)")
        }

        return true
    }

    //===================================================================================
    //MARK: UISceneSession Lifecycle
    //===================================================================================

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) { }
}

