import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';
import 'package:http/http.dart' as http;

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {

  String walletAddress="",walletBalance="",hashValue="";
  EtherAmount? balanceEth;
  late Web3App web3app;
  bool isConnected =false;
  final TextEditingController amountController =  TextEditingController();

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    initializeWalletConnect();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: Text("Wallet App",style: TextStyle(
          color: Colors.white
        ),),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(10),
        child: Center(
          child: Column(
            spacing: 10,
            children: [
              Text(walletAddress),
              Text(walletBalance),
              if(isConnected==false)
                ElevatedButton(
                    onPressed: ()async{
                      await connectWallet(context);
                    },
                    child: Text("Connect Wallet")),
              if(isConnected==true)
              TextFormField(
                controller: amountController,
                decoration: InputDecoration(
                  fillColor: Colors.white,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                        width: 1,
                        color: Colors.grey)
                  )
                ),
              ),
              if(isConnected==true)
              ElevatedButton(
                  onPressed: (){
                    sendETHToContract("YOUR CONTRACT ADDRESS", double.parse(amountController.text), context);
                  },
                  child: Text("Send Eth")),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> initializeWalletConnect() async {
    web3app = await Web3App.createInstance(
      projectId: 'YOUR PROJECT ID', // Replace with your project ID
      relayUrl: 'wss://relay.walletconnect.com',
      metadata: PairingMetadata(
          name: 'My App',
        description: 'A description of my app',
        url: 'https://mywalletApp.com',
        icons: ['https://mydapp.com/logo.png'],
      ),
    );
  }

  Future<void> connectWallet(BuildContext context) async {
    try {
      final ConnectResponse resp = await web3app.connect(
        requiredNamespaces: {
          'eip155': const RequiredNamespace(
            chains: ['eip155:11155111'],
            methods: [
              'eth_sendTransaction',
              'personal_sign',
              'eth_estimateGas',
              'eth_gasPrice',
            ],
            events: ['chainChanged'],
          ),
        },
      );

      await launchUrlString(resp.uri.toString()); // Open MetaMask

      web3app.onSessionConnect.subscribe((session) {
        if (session != null &&
            session.session.namespaces.containsKey('eip155') &&
            session.session.namespaces['eip155']!.accounts.isNotEmpty) {
          final String connectedAddress =
          session.session.namespaces['eip155']!.accounts[0];

          final cleanAddress = connectedAddress.replaceAll('eip155:11155111:', '');
           setState(() {
             walletAddress = cleanAddress;
             getBalance(walletAddress); // Fetch balance
             isConnected=true;
           });
          log('Connected Address: $walletAddress');
        } else {
          log('No accounts found in session.');
        }
      });

      web3app.onSessionDelete.subscribe((session) {
        log('Disconnected: $session');
      });
    } catch (e) {
      log('Error connecting to MetaMask: $e');
    }
  }

  Future<void> getBalance(String address) async {
    try {
      final client = Web3Client(
        'https://eth-sepolia.g.alchemy.com/v2/YOUR PROJECT ID',
        http.Client(),
      );

      EtherAmount balance =
      await client.getBalance(EthereumAddress.fromHex(address));

      setState(() {
        balanceEth = balance;
        walletBalance = balance.getValueInUnit(EtherUnit.ether).toString();

      });
      log('Balance: ${balance.getValueInUnit(EtherUnit.ether)} ETH');
    } catch (e) {
      log('Error fetching balance: $e');
    }
  }

  Future<void> sendETHToContract(String contractAddress, double amountEth,BuildContext context) async {
    if (walletAddress.isEmpty) {
      log('Wallet is not connected');
      return;
    }

    final sessions = web3app.getActiveSessions(); // Use await here
    if (sessions.isEmpty) {
      log('No active WalletConnect session.');
      return;
    }

    final topic = sessions.keys.first; // Ensure a valid session is used

    try {
      // Create Web3Client for interacting with the Ethereum network
      final client = Web3Client(
        'https://eth-sepolia.g.alchemy.com/v2/YOUR PROJECT ID',
        http.Client(),
      );

      // Convert ETH amount to Wei (1 ETH = 1e18 Wei)
      final BigInt amountInWei = BigInt.from((amountEth * 1e18).toInt());

      // Fetch current gas price
      final EtherAmount gasPrice = await client.getGasPrice();
      log('Gas Price: $gasPrice');
      int gasPriceInt = gasPrice.getInWei.toInt();
      log("gasPriceInt$gasPriceInt");
      // Estimate gas limit for the transaction
      final BigInt estimatedGasLimit = await client.estimateGas(
        sender: EthereumAddress.fromHex(walletAddress),
        to: EthereumAddress.fromHex(contractAddress),
        value: EtherAmount.inWei(amountInWei),
      );
      log('Estimated Gas Limit: $estimatedGasLimit');

      // Prepare the transaction data
      final transaction = [
        {
          'from': walletAddress,
          'to': contractAddress,
          'value': '0x${amountInWei.toRadixString(16)}', // Amount in Wei
          'gas': '0x${estimatedGasLimit.toRadixString(16)}', // Gas limit in hex
          'gasPrice': '0x${gasPrice.getValueInUnit(EtherUnit.wei).toInt().toRadixString(16)}', // Gas price in hex
        }
      ];

      log('Sending transaction...');
      log('Transaction Details: ${jsonEncode(transaction)}');
      await launchUrlString('https://metamask.app.link/wc?uri=${Uri.encodeComponent(transaction.toString())}');
      // Send the transaction request to WalletConnect
      final result = await web3app.request(
        topic: topic,
        chainId: 'eip155:11155111',
        request: SessionRequestParams(
          method: 'eth_sendTransaction',
          params: transaction,
        ),
      );
      log('Transaction sent! Tx Hash: $result');
      setState(() {
        hashValue=result;
      });
    } catch (e, stackTrace) {
      // Catch network or RPC related errors
      if (e is SocketException) {
        log('Network error: Unable to connect to the Ethereum network. Please check your internet connection.');
      } else if (e is RPCError) {
        log('RPC Error: $e');
      } else {
        log('Error sending ETH: $e');
      }

      log('Stack trace: $stackTrace');
    }
  }
}
