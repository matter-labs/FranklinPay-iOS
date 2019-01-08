//
//  WalletViewController.swift
//  DiveLane
//
//  Created by Anton Grigorev on 08/09/2018.
//  Copyright © 2018 Matter Inc. All rights reserved.
//

import UIKit
import Web3swift
import EthereumAddress
import BigInt

class WalletViewController: UIViewController {

    @IBOutlet weak var walletTableView: UITableView!
    @IBOutlet weak var blockchainControl: UISegmentedControl!

    let conversionService = RatesService.service

    var tokensService = TokensService()
    var walletsService = WalletsService()
    var wallets: [WalletModel]?
    var twoDimensionalTokensArray: [ExpandableTableTokens] = []
    var twoDimensionalUTXOsArray: [ExpandableTableUTXOs] = []

    var chosenUTXOs: [TableUTXO] = []

    let animation = AnimationController()

    let design = DesignElements()

    private enum Blockchain: Int {
        case ether = 0
        case plasma = 1
    }

    lazy var refreshControl: UIRefreshControl = {
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action:
        #selector(self.handleRefresh(_:)),
                for: UIControl.Event.valueChanged)
        refreshControl.tintColor = UIColor.blue

        return refreshControl
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.tabBarController?.tabBar.selectedItem?.title = nil
        self.setupTableView()
        self.navigationItem.setRightBarButton(settingsWalletBarItem(), animated: false)
    }
    
    private func setupTableView() {
        let nibToken = UINib.init(nibName: "TokenCell", bundle: nil)
        self.walletTableView.delegate = self
        self.walletTableView.dataSource = self
        self.walletTableView.tableFooterView = UIView()
        self.walletTableView.addSubview(self.refreshControl)
        self.walletTableView.register(nibToken, forCellReuseIdentifier: "TokenCell")
    }

    func initDatabase() {
        guard let wallets = try? WalletsService().getAllWallets() else {
            return
        }
        self.wallets = wallets
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.title = "Wallets"
        self.tabBarController?.tabBar.selectedItem?.title = nil

    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        animation.waitAnimation(isEnabled: true, notificationText: "Loading initial data", on: self.view)
        twoDimensionalTokensArray.removeAll()
        twoDimensionalUTXOsArray.removeAll()
        updateTable()
    }

    func unselectAllTokens() {
        var indexPath = IndexPath(row: 0, section: 0)
        for wallet in twoDimensionalTokensArray {
            for _ in wallet.tokens {
                self.twoDimensionalTokensArray[indexPath.section].tokens[indexPath.row].isSelected = false
                if let cell = walletTableView.cellForRow(at: indexPath) as? TokenCell {
                    cell.changeSelectButton(isSelected: false)
                }
                indexPath.row += 1
            }
            indexPath.section += 1
            indexPath.row = 0
        }
    }

    func unselectAllUTXOs() {
        var indexPath = IndexPath(row: 0, section: 0)
        for wallet in twoDimensionalUTXOsArray {
            for _ in wallet.utxos {
                self.twoDimensionalUTXOsArray[indexPath.section].utxos[indexPath.row].isSelected = false
                guard let cell = walletTableView.cellForRow(at: indexPath) as? TokenCell else {return}
                cell.changeSelectButton(isSelected: false)
                indexPath.row += 1
            }
            indexPath.section += 1
            indexPath.row = 0
        }
    }

    func selectToken(cell: UITableViewCell) {
        unselectAllTokens()
        guard let cell = cell as? TokenCell else {return}
        guard let indexPathTapped = walletTableView.indexPath(for: cell) else {return}
        let token = twoDimensionalTokensArray[indexPathTapped.section].tokens[indexPathTapped.row]
        print(token)
        CurrentToken.currentToken = token.token
        do {
            try WalletsService().selectWallet(wallet: token.inWallet)
            self.twoDimensionalTokensArray[indexPathTapped.section].tokens[indexPathTapped.row].isSelected = true
            cell.changeSelectButton(isSelected: true)
        } catch {
            return
        }
    }

    func selectUTXO(cell: UITableViewCell) {
//        unselectAllUTXOs()
        guard let cell = cell as? TokenCell else {return}
        guard let indexPathTapped = walletTableView.indexPath(for: cell) else {return}
        let utxo = twoDimensionalUTXOsArray[indexPathTapped.section].utxos[indexPathTapped.row]
        print(utxo)
        let selected = twoDimensionalUTXOsArray[indexPathTapped.section].utxos[indexPathTapped.row].isSelected
        if selected {
            for i in 0..<chosenUTXOs.count where chosenUTXOs[i] == utxo {
                chosenUTXOs.remove(at: i)
                break
            }
        } else {
            guard chosenUTXOs.count < 2 else {return}
            if let firstUTXO = chosenUTXOs.first {
                guard utxo.inWallet == firstUTXO.inWallet else {return}
                chosenUTXOs.append(utxo)
            } else {
                chosenUTXOs.append(utxo)
            }
        }
        print(chosenUTXOs.count)
        twoDimensionalUTXOsArray[indexPathTapped.section].utxos[indexPathTapped.row].isSelected = !selected
        cell.changeSelectButton(isSelected: !selected)
        if chosenUTXOs.count == 2 {
            Alerts().showAccessAlert(for: self, with: "Merge UTXOs?") { [weak self] (result) in
                if result {
                    self?.formMergeUTXOsTransaction(forWallet: utxo.inWallet)
                }
            }
        }
    }

    func formMergeUTXOsTransaction(forWallet: WalletModel) {
        var inputs = [TransactionInput]()
        var mergedAmount: BigUInt = 0
        do {
            for utxo in chosenUTXOs {
                let input = try? utxo.utxo.toTransactionInput()
                if let i = input {
                    inputs.append(i)
                    mergedAmount += i.amount
                }
            }
            guard let address = EthereumAddress(forWallet.address) else {return}
            let output = try TransactionOutput(outputNumberInTx: 0, receiverEthereumAddress: address, amount: mergedAmount)
            let outputs = [output]
            let transaction = try PlasmaTransaction(txType: .merge, inputs: inputs, outputs: outputs)
            checkPassword(forWallet: forWallet) { [weak self] (password) in
                self?.enterPincode(for: transaction, withPassword: password)
            }
        } catch let error {
            print(error.localizedDescription)
        }
    }

    func checkPassword(forWallet: WalletModel, completion: @escaping (String?) -> Void) {
        do {
            let passwordItem = KeychainPasswordItem(service: KeychainConfiguration.serviceNameForPassword,
                                                    account: "\(forWallet.name)-password",
                accessGroup: KeychainConfiguration.accessGroup)
            let keychainPassword = try passwordItem.readPassword()
            completion(keychainPassword)
        } catch {
            completion(nil)
        }
    }

    func enterPincode(for transaction: PlasmaTransaction, withPassword: String?) {
        let enterPincode = EnterPincodeViewController(from: .transaction, for: transaction, withPassword: withPassword ?? "", isFromDeepLink: false)
        self.navigationController?.pushViewController(enterPincode, animated: true)
    }

    @objc func handleRefresh(_ refreshControl: UIRefreshControl) {
//        twoDimensionalTokensArray.removeAll()
//        twoDimensionalUTXOsArray.removeAll()
//        reloadDataInTable()
        updateTable()
    }

    func reloadDataInTable() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshControl.endRefreshing()
            self?.walletTableView.reloadData()
            self?.animation.waitAnimation(isEnabled: false, notificationText: "Loading initial data", on: (self?.view)!)
        }
    }

    func updateTable() {
        twoDimensionalTokensArray.removeAll()
        twoDimensionalUTXOsArray.removeAll()
        reloadDataInTable()
        
        switch blockchainControl.selectedSegmentIndex {
        case Blockchain.ether.rawValue:
            DispatchQueue.global().async { [weak self] in
                self?.updateEtherBlockchain()
            }
        default:
            DispatchQueue.global().async { [weak self] in
                self?.updatePlasmaBlockchain()
            }
        }
    }

    private func settingsWalletBarItem() -> UIBarButtonItem {
        let addButton = UIBarButtonItem(image: UIImage(named: "settings_blue"),
                                        style: .plain,
                                        target: self,
                                        action: #selector(settingsWallet))
        return addButton
    }

    @objc func settingsWallet() {
        //let walletsViewController = WalletsViewController()
        let settingsViewController = SettingsViewController()
        self.navigationController?.pushViewController(settingsViewController, animated: true)
    }

    @IBAction func addWallet(_ sender: UIButton) {
        let addWalletViewController = AddWalletViewController(isNavigationBarNeeded: true)
        self.navigationController?.pushViewController(addWalletViewController, animated: true)
    }

    func getTokensListForEtherBlockchain(completion: @escaping () -> Void) {
        guard let wallets = wallets else {
            return
        }
        let networkID = CurrentNetwork().getNetworkID()
        for wallet in wallets {
            guard let tokens = try? TokensService().getAllTokens(for: wallet, networkId: networkID) else {
                completion()
                return
            }
            guard let selectedWallet = try? keysService.getSelectedWallet() else {
                completion()
                return
            }
            let isSelectedWallet = wallet == selectedWallet ? true : false
//            let expandableTokens = ExpandableTableTokens(isExpanded: isSelectedWallet,
//                                                         tokens: tokens.map {
//                                                            TableToken(token: $0,
//                                                                       inWallet: wallet,
//                                                                       isSelected: ($0 == CurrentToken.currentToken) && isSelectedWallet)
//            })
            let expandableTokens = ExpandableTableTokens(isExpanded: true,
                                                         tokens: tokens.map {
                                                            TableToken(token: $0,
                                                                       inWallet: wallet,
                                                                       isSelected: ($0 == CurrentToken.currentToken) && isSelectedWallet)
            })
            twoDimensionalTokensArray.append(expandableTokens)
            completion()
        }
    }

    func updatePlasmaBlockchain() {
        initDatabase()
//        twoDimensionalUTXOsArray.removeAll()
        guard let wallets = wallets else {return}
        let network = CurrentNetwork.currentNetwork
        for wallet in wallets {
            guard let ethAddress = EthereumAddress(wallet.address) else {
                self.reloadDataInTable()
                return
            }
            let mainnet = network.chainID == Networks.Mainnet.chainID
            let testnet = !mainnet && network.chainID == Networks.Rinkeby.chainID
            if !testnet && !mainnet {
                self.reloadDataInTable()
                return
            }
            guard let utxos = try? PlasmaService().getUTXOs(for: ethAddress, onTestnet: testnet) else {
                self.reloadDataInTable()
                return
            }
            let expandableUTXOS = ExpandableTableUTXOs(isExpanded: true,
                                                       utxos: utxos.map {
                                                        TableUTXO(utxo: $0,
                                                                  inWallet: wallet,
                                                                  isSelected: false)
            })
            self.twoDimensionalUTXOsArray.append(expandableUTXOS)
            if wallet == wallets.last {
                self.reloadDataInTable()
            }
        }
    }

    func updateEtherBlockchain() {
        initDatabase()
//        self.twoDimensionalTokensArray.removeAll()
        self.getTokensListForEtherBlockchain { [weak self] in
            self?.reloadDataInTable()
        }
    }

    @IBAction func blockchainChanged(_ sender: UISegmentedControl) {
        twoDimensionalTokensArray.removeAll()
        twoDimensionalUTXOsArray.removeAll()
        reloadDataInTable()
        updateTable()
    }

}

extension WalletViewController: UITableViewDelegate, UITableViewDataSource {

    func backgroundForHeaderInEtherBlockchain(section: Int) -> UIView {
        let backgroundView = design.tableViewHeaderBackground(in: self.view)

        let walletButton = design.tableViewHeaderWalletButton(in: self.view,
                                                              withTitle: "Wallet \(twoDimensionalTokensArray[section].tokens.first?.inWallet.name ?? "")",
            withTag: section)
        walletButton.addTarget(self, action: #selector(handleExpandClose), for: .touchUpInside)
        backgroundView.addSubview(walletButton)

        let addButton = design.tableViewAddTokenButton(in: self.view, withTag: section)
        addButton.addTarget(self, action: #selector(handleAddToken), for: .touchUpInside)
        backgroundView.addSubview(addButton)

        return backgroundView
    }

    func backgroundForHeaderInPlasmaBlockchain(section: Int) -> UIView {
        let backgroundView = design.tableViewHeaderBackground(in: self.view)

        let walletButton = design.tableViewHeaderWalletButton(in: self.view,
                                                              withTitle: "Wallet \(twoDimensionalUTXOsArray[section].utxos.first?.inWallet.name ?? "")",
            withTag: section)
        walletButton.addTarget(self, action: #selector(handleExpandClose), for: .touchUpInside)
        backgroundView.addSubview(walletButton)

        return backgroundView
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let background: UIView
        switch blockchainControl.selectedSegmentIndex {
        case Blockchain.ether.rawValue:
            background = backgroundForHeaderInEtherBlockchain(section: section)
        default:
            background = backgroundForHeaderInPlasmaBlockchain(section: section)
        }
        return background
    }

    @objc func handleExpandClose(button: UIButton) {

        let section = button.tag

        var indexPaths = [IndexPath]()

        let isExpanded: Bool

        switch blockchainControl.selectedSegmentIndex {
        case Blockchain.ether.rawValue:
            for row in twoDimensionalTokensArray[section].tokens.indices {
                let indexPath = IndexPath(row: row, section: section)
                indexPaths.append(indexPath)
            }

            isExpanded = twoDimensionalTokensArray[section].isExpanded
            twoDimensionalTokensArray[section].isExpanded = !isExpanded
        default:
            for row in twoDimensionalUTXOsArray[section].utxos.indices {
                let indexPath = IndexPath(row: row, section: section)
                indexPaths.append(indexPath)
            }

            isExpanded = twoDimensionalUTXOsArray[section].isExpanded
            twoDimensionalUTXOsArray[section].isExpanded = !isExpanded
        }
        if isExpanded {
            walletTableView.deleteRows(at: indexPaths, with: .fade)
        } else {
            walletTableView.insertRows(at: indexPaths, with: .fade)
        }
    }

    @objc func handleAddToken(button: UIButton) {
        let section = button.tag
        let wallet = twoDimensionalTokensArray[section].tokens.first?.inWallet
        let token = twoDimensionalTokensArray[section].tokens.first
        do {
            try WalletsService().selectWallet(wallet: wallet!)
            CurrentToken.currentToken = token?.token
            let searchTokenController = SearchTokenViewController(for: wallet)
            self.navigationController?.pushViewController(searchTokenController, animated: true)
        } catch let error {
            print(error)
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        switch blockchainControl.selectedSegmentIndex {
        case Blockchain.ether.rawValue:
            return twoDimensionalTokensArray.count
        default:
            return twoDimensionalUTXOsArray.count
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 45
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch blockchainControl.selectedSegmentIndex {
        case Blockchain.ether.rawValue:
            if !twoDimensionalTokensArray[section].isExpanded {
                return 0
            }

            return twoDimensionalTokensArray[section].tokens.count
        default:
            if !twoDimensionalUTXOsArray[section].isExpanded {
                return 0
            }

            return twoDimensionalUTXOsArray[section].utxos.count
        }

    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "TokenCell",
                                                       for: indexPath) as? TokenCell else {
                                                        return UITableViewCell()
        }
        cell.link = self

        switch blockchainControl.selectedSegmentIndex {
        case Blockchain.ether.rawValue:
            let token = twoDimensionalTokensArray[indexPath.section].tokens[indexPath.row]
            cell.configureForEtherBlockchain(token: token.token,
                                             forWallet: token.inWallet,
                                             isSelected: token.isSelected)
        default:
            let utxo = twoDimensionalUTXOsArray[indexPath.section].utxos[indexPath.row]
            cell.configureForPlasmaBlockchain(utxo: utxo.utxo, forWallet: utxo.inWallet)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

        switch blockchainControl.selectedSegmentIndex {
        case Blockchain.ether.rawValue:
            guard let indexPathForSelectedRow = tableView.indexPathForSelectedRow else {
                return
            }
            let cell = tableView.cellForRow(at: indexPathForSelectedRow) as? TokenCell

            guard let selectedCell = cell else {
                return
            }

            guard let indexPathTapped = walletTableView.indexPath(for: selectedCell) else {
                return
            }

            let token = twoDimensionalTokensArray[indexPathTapped.section].tokens[indexPathTapped.row]

            let tokenViewController = TokenViewController(
                wallet: token.inWallet,
                token: token.token,
                tokenBalance: selectedCell.balance.text ?? "0")
            self.navigationController?.pushViewController(tokenViewController, animated: true)
            tableView.deselectRow(at: indexPath, animated: true)
        default:
            tableView.deselectRow(at: indexPath, animated: true)
        }
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard blockchainControl.selectedSegmentIndex == Blockchain.ether.rawValue else {return}
        let token = twoDimensionalTokensArray[indexPath.section].tokens[indexPath.row].token
        let wallet = twoDimensionalTokensArray[indexPath.section].tokens[indexPath.row].inWallet
        print(token.name)
        let isEtherToken = token == ERC20TokenModel(isEther: true)
        let plasmaBlockchain = blockchainControl.selectedSegmentIndex == Blockchain.plasma.rawValue
        if isEtherToken || plasmaBlockchain {
            return
        }
        if editingStyle == .delete {
            let networkID = CurrentNetwork().getNetworkID()
            do {
                try TokensService().deleteToken(token: token, wallet: wallet, networkId: networkID)
                self.updateTable()
            } catch {
                return
            }
        }
    }
}