//
//  NetworksViewController.swift
//  DiveLane
//
//  Created by Anton Grigorev on 08/09/2018.
//  Copyright © 2018 Matter Inc. All rights reserved.
//

import UIKit
import Web3swift

class NetworksViewController: BasicViewController {
    
    // MARK: - Outlets

    @IBOutlet weak var networksTableView: BasicTableView!

    // MARK: - Internal vars
    
    internal var networks: [Web3Network] = []
    
    // MARK: - Lyfesycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTableView()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setNavigation(hidden: false)
        getNetworks()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setNavigation(hidden: true)
    }
    
    // MARK: - Main setup
    
    func setNavigation(hidden: Bool) {
        navigationController?.setNavigationBarHidden(hidden, animated: true)
        navigationController?.makeClearNavigationController()
    }
    
    private func setupTableView() {
        let nibToken = UINib.init(nibName: "NetworksCell", bundle: nil)
        networksTableView.delegate = self
        networksTableView.dataSource = self
        let footerView = UIView()
        footerView.backgroundColor = Colors.background
        networksTableView.tableFooterView = footerView
        networksTableView.register(nibToken, forCellReuseIdentifier: "NetworksCell")
        networks.removeAll()
    }
    
    // MARK: - Table view updates

    func getNetworks() {
        DispatchQueue.global().async { [unowned self] in
            let basicNetworks: [Networks] = [.Mainnet,
                                             .Rinkeby,
                                             .Ropsten]
            var web3networks: [Web3Network]
            let basicWeb3Nets = basicNetworks.map({
                Web3Network(network: $0)
            })
            web3networks = basicWeb3Nets
            let xdai = Web3Network(id: 100, name: "xDai", endpoint: "https://dai.poa.network")
            web3networks.append(xdai)
            self.networks = web3networks
            self.reloadDataInTable()
        }
    }
    
    func reloadDataInTable() {
        DispatchQueue.main.async { [weak self] in
            self?.networksTableView.reloadData()
        }
    }

}
