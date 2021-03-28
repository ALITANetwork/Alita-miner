Alitacoin-Miner
===================================================================
 Alitacoin-Miner is a Miner for Alitacoin
 
Here let's introduce the stack of the Alita Network.
There are three main components:

* Computing network, PC version container service based on k3s and Task Executor based on Android. We also developed the container orchestration service for the business clients.

* Storage network, the data to process is stored in the private forked instance of IPFS network, which is extended to read and write row based flat files.

* Accounting network, token mining, payment and smart contract(in Java and based on CIYAM), private forked from burstcoin. We plan to port to substrate chain and refactor the contract in Ink!. And also UIs will be redesigned.

 CentOS Instructions
 -----------
 ### These steps will install the following dependencies:
 * Docker
 * Jq

 1. Then download the AlitaMiner Client:
    
        wget http://wallet2.alita.services:8080/Alita_verifier_mining_client-1.0.0.tar.gz
 
     Or you can click [here](http://wallet2.alita.services:8080/Alita_verifier_mining_client-1.0.0.tar.gz) to download Alita-Miner Client
 
 2. Then run:
    
        tar -zxvf Alita_verifier_mining_client-1.0.0.tar.gz
 
 3. and:
    
        cd Alita-miner

 4. ### edit ``../Alita-miner/alita.conf `` with text editor to configure miner,and all the config are required!
        
    * key=
      
          This is required a ``Alita Numeric ID`` to create PlotFiles for your miner, for example: ``9646347366529451968`` is a accurately property.
      
          (If you do not have a ``Alita Numeric ID``,please visit the [Alita Network](http://wallet.alita.services:8080) and create a Alita account for yourself.Then click the copy Numeric Account ID or check your account information to get your ``Alita numeric ID``)

    * startNonce=
        
          The startNonce is a random number you need to set to generate a plotfile.This config decide your plotfile form which Nonce.(a number whatever you want from 0 to 18446744073709551615).

    * nonces=

          The number of Nonce you would create to mine.A nonce would occupied 256KB in your devices.And: 1GB=4096,256GB=1048574,512GB=2097152,1TB=4194304
      
    * dir=

          List of plot paths separated with.example:dir=/usr/local/plots

    * passPhrase=""

          secretPhrase/password of mining Alita account.when you are mining Alita,it would send your passPhrase on commit results!
          (Don't missing the "" because it may failed when you run the miner shell.)

    * alitaServer=http://wallet.alita.services:8125

          A AlitaServer to commit your mining info.Now use http://wallet.alita.services:8125 in Alita TestNet!






 5. Run ``startup.sh`` to start Mining Alita!

        sudo sh startup.sh

    And then,a Alita Miner Images would be build and run automatic in a container.You can get Miner log in the dir you configed.example: /home/baohui/plots/plots/9646347366529451968_2312424_4096/miner.log 

 Ubuntu Instructions
 ---------------------
 ### It's coming soon!
