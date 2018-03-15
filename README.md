# btap_gather_results
A script that can be used to download and organize btap results.

ssh -i server.pem Unbutu#ec-2123-121-121-12

YOu 'll get in to the amazon server... then you will need to log into the docker container that is the running the webserver. TO find the server run 

docker ps

You'll see a docker container running that looks like this. 

osserver_web.

Use the Container id of the server to enter the web server

docker exec -it 2f12a47beedf /bin/bash

Once you are there, you can use git to clone this repository, then enter the repository and run 'bundle install' 

you can run the script with 'bundle exec ruby gather_results.rb'

You shoudl install Nano
sudo apt-get update && sudo apt-get install nano


