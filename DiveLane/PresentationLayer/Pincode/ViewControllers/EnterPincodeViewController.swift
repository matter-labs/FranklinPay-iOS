//
//  EnterPincodeViewController.swift
//  DiveLane
//
//  Created by Anton Grigorev on 13/09/2018.
//  Copyright © 2018 Matter Inc. All rights reserved.
//

import UIKit
import LocalAuthentication
import Web3swift

class EnterPincodeViewController: PincodeViewController {

    var pincode: String = ""
    var status: PincodeEnterStatus = .enter

    var enterCase: EnterPincodeCases = .enterWallet
    var plasmaTX: PlasmaTransaction?
    var etherTX: WriteTransaction?
    var fromDeepLink: Bool = false
    
    let alerts = Alerts()
    let plasmaService = PlasmaService()
    
    convenience init<T>(for enterCase: EnterPincodeCases, data: T?, fromDeepLink: Bool) {
        self.init()
        self.fromDeepLink = fromDeepLink
        self.enterCase = enterCase
        if T.self == PlasmaTransaction.self {
            self.plasmaTX = data as? PlasmaTransaction
        } else if T.self == WriteTransaction.self {
            self.etherTX = data as? WriteTransaction
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationController?.navigationBar.isHidden = enterCase == .transaction
            ? true
            : false
        changePincodeStatus(.enter)
        numsIcons = [firstNum, secondNum, thirdNum, fourthNum]
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        enterWithBiometrics()
    }

    override func viewWillAppear(_ animated: Bool) {
        self.navigationController?.setNavigationBarHidden(true, animated: false)
        super.viewWillAppear(animated)
        let context = LAContext()
        var error: NSError?
        if !context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            disableBiometricsButton(true)
            biometricsButton.isUserInteractionEnabled = false
        }
    }

    func disableBiometricsButton(_ disable: Bool = false) {
        biometricsButton.alpha = disable ? 0.0 : 1.0
        biometricsButton.isUserInteractionEnabled = !disable
    }

    func changePincodeStatus(_ newStatus: PincodeEnterStatus) {
        status = newStatus
        messageLabel.text = status.rawValue
        if status == .wrong {
            pincode = ""
            changeNumsIcons(0)
        } else if status == .ready {
            enterWithPincode()
        }
    }
    
    override func numberPressedAction(number: String) {
        if status == .enter {
            pincode += number
            changeNumsIcons(pincode.count)
            if pincode.count == 4 {
                let newStatus: PincodeEnterStatus = checkPin(pincode) ? .ready : .wrong
                changePincodeStatus(newStatus)
            }
        } else if status == .wrong {
            changePincodeStatus(.enter)
            pincode += number
            changeNumsIcons(pincode.count)
        }
    }
    
    override func deletePressedAction() {
        if pincode != "" {
            pincode.removeLast()
            changeNumsIcons(pincode.count)
        }
    }
    
    override func biometricsPressedAction() {
        enterWithBiometrics()
    }
    
    func enterWithBiometrics() {
        
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            var type = "Touch ID"
            if #available(iOS 11, *) {
                switch context.biometryType {
                case .touchID:
                    type = "Touch ID"
                case .faceID:
                    type = "Face ID"
                case .none:
                    type = "Error"
                }
            }
            
            let reason = "Authenticate with " + type
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                   localizedReason: reason,
                                   reply: { [weak self] (success, _) in
                                    if success {
                                        self?.enterWithPincode()
                                    }
            })
        }
    }

    func checkPin(_ passcode: String) -> Bool {
        do {
            let pincodeItem = KeychainPasswordItem(service: KeychainConfiguration.serviceNameForPincode,
                    account: "pincode",
                    accessGroup: KeychainConfiguration.accessGroup)
            let keychainPincode = try pincodeItem.readPassword()
            return pincode == keychainPincode
        } catch {
            fatalError("Error reading password from keychain - \(error)")
        }
    }

    func enterWithPincode() {
        switch enterCase {
        case .transaction:
            if let etherTx = self.etherTX {
                sendEtherTx(etherTx)
            } else if let plasmaTX = self.plasmaTX {
                sendPlasmaTx(plasmaTX)
            } else {
                alerts.showErrorAlert(for: self, error: "Transaction is wrong") { [unowned self] in
                    self.navigationController?.popViewController(animated: true)
                }
            }
        default:
            let startViewController = AppController().goToApp()
            startViewController.view.backgroundColor = Colors.firstMain
            UIApplication.shared.keyWindow?.rootViewController = startViewController
        }
    }

    func sendPlasmaTx(_ tx: PlasmaTransaction) {
        DispatchQueue.global().async { [unowned self] in
            guard let wallet = CurrentWallet.currentWallet else {
                self.alerts.showErrorAlert(for: self, error: "Can't figure wallet to use") {
                    self.navigationController?.popViewController(animated: true)
                }
                return
            }
            let testnet: Bool
            if CurrentNetwork.currentNetwork == Web3Network(network: .Mainnet) {
                testnet = false
            } else if CurrentNetwork.currentNetwork == Web3Network(network: .Rinkeby) {
                testnet = true
            } else {
                self.alerts.showErrorAlert(for: self, error: "Wrong network \(CurrentNetwork.currentNetwork.name), please choose Mainnet or Rinkeby for tests") {
                    self.navigationController?.popViewController(animated: true)
                }
                return
            }
            do {
                let password = try wallet.getPassword()
                let privateKey = try wallet.getPrivateKey(withPassword: password)
                let privateKeyData = Data(hex: privateKey)
                let signedTx = try tx.sign(privateKey: privateKeyData)
                
                let result = try self.plasmaService.sendRawTX(transaction: signedTx, onTestnet: testnet)
                if result {
                    self.alerts.showSuccessAlert(for: self) {
                        self.returnToStartTab()
                    }
                } else {
                    self.alerts.showErrorAlert(for: self, error: "Sending failed") {
                        self.returnToStartTab()
                    }
                }
            } catch let error {
                self.alerts.showErrorAlert(for: self, error: error) {
                    self.returnToStartTab()
                }
            }
        }
    }

    func sendEtherTx(_ tx: WriteTransaction) {
        DispatchQueue.global().async { [unowned self] in
            guard let wallet = CurrentWallet.currentWallet else {
                self.alerts.showErrorAlert(for: self, error: "Can't figure wallet to use") {
                    self.navigationController?.popViewController(animated: true)
                }
                return
            }
            do {
                let password = try wallet.getPassword()
                let result = try tx.send(password: password, transactionOptions: nil)
                let hash = result.hash
                self.alerts.showSuccessAlert(for: self, with: "Transaction hash: \(hash)", completion: {
                    self.returnToStartTab()
                })
            } catch let error {
                self.alerts.showErrorAlert(for: self, error: error) {
                    self.returnToStartTab()
                }
            }
            
        }
    }

    func returnToStartTab() {
        DispatchQueue.main.async {
            let startViewController = AppController().goToApp()
            startViewController.view.backgroundColor = Colors.firstMain
            UIApplication.shared.keyWindow?.rootViewController = startViewController
        }
    }

    
}