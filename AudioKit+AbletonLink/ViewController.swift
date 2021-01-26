//
//  ViewController.swift
//  AudioKitTest
//
//  Created by Kevin Schlei on 12/29/20.
//

import UIKit
import AudioKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Show link settings view controller
        if let linkSettingsViewController = ABLLinkSettingsViewController.instance(ABLLinkManager.shared.linkRef) {
            linkSettingsViewController.willMove(toParent: self)
            addChild(linkSettingsViewController)
            linkSettingsViewController.didMove(toParent: self)
            linkSettingsViewController.view.frame = CGRect(x: 0, y: 0, width: 300, height: 400)
            view.addSubview(linkSettingsViewController.view)
        }
    }
}
