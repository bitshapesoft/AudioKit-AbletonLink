//
//  LinkObject.swift
//  AudioKitTest
//
//  Created by Kevin Schlei on 1/20/21.
//

import AVFoundation
import AudioKit
import CAudioKit

//‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
//MARK: LinkObject
//_______________________________________________________________________________________

/// Reads from the table sequentially and repeatedly at given frequency.
/// Linear interpolation is applied for table look up from internal phase values.
///
public class LinkObject: Node, AudioUnitContainer, Tappable, Toggleable {

    /// Unique four-letter identifier "link"
    public static let ComponentDescription = AudioComponentDescription(generator: "link")

    /// Internal type of audio unit for this node
    public typealias AudioUnitType = InternalAU

    /// Internal audio unit
    public private(set) var internalAU: AudioUnitType?

    // MARK: - Parameters

    // MARK: - Audio Unit

    /// Internal Audio Unit for LinkObject
    public class InternalAU: AudioUnitBase {
        /// Get an array of the parameter definitions
        /// - Returns: Array of parameter definitions
        public override func getParameterDefs() -> [NodeParameterDef] {
            []
        }

        /// Create the DSP Refence for this node
        /// - Returns: DSP Reference
        public override func createDSP() -> DSPRef {
            akCreateDSP("LinkObjectDSP")
        }
    }

    // MARK: - Initialization

    /// Initialize this link node
    ///
    public init() {
        super.init(avAudioNode: AVAudioNode())

        instantiateAudioUnit { avAudioUnit in
            self.avAudioUnit = avAudioUnit
            self.avAudioNode = avAudioUnit

            guard let audioUnit = avAudioUnit.auAudioUnit as? AudioUnitType else {
                fatalError("Couldn't create audio unit")
            }
            self.internalAU = audioUnit
            self.stop()
        }
    }
}
