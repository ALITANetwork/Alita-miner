#!/bin/sh
#判断是否从外部挂载plot文件
./alita --id $numericAccountId --sn $startNonce --n $nonces --path /usr/local/plots -d

#修改miner的properties属性
sed -i "s#^plotPaths=.*#plotPaths=/usr/local/plots#g" jminer.properties
sed -i "s#^poolMining=.*#poolMining=false#g" jminer.properties
sed -i "s#^numericAccountId=.*#numericAccountId=$numericAccountId#g" jminer.properties
sed -i "s#^soloServer=.*#soloServer=${soloServer}#g" jminer.properties
sed -i "s#^walletServer=.*#walletServer=#g" jminer.properties
sed -i "s#^useOpenCl=.*#useOpenCl=false#g" jminer.properties
sed -i "s#^debug=.*#debug=false#g" jminer.properties
sed -i "s#^passPhrase=.*#passPhrase=${passPhrase}#g" jminer.properties

#file_name=`find /usr/local/alita -name '*RELEASE.jar' |sed -n "1p"`
#CurrentVersion=`echo $file_name|cut -d "-" -f3`
#run_process=raptorcoin-jminer-${CurrentVersion}-RELEASE.jar
#echo $run_process

nohup java -jar -d64 -XX:+UseG1GC ./Alita-miner-v1.0.0.jar >> /usr/local/plots/miner.log 2>&1 &

tail -f /dev/null

fg %1

