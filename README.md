# BTAP Gather Results

## Introduction

A script that can be used to download and organize btap results from the AWS server.

If you are using PAT for BTAP simulations:

Start the PAT analysis with the PAT GUI.  This may take up to 10 minutes to begin.  An `ec2_server_key.pem` file will be automatically generated for you.  Click the `Run Entire Workflow` once the option to do so becomes available in order to start the analysis.  Click the View AWS Console button to view the progress of the analysis in your Internet browser.  This browser window will be necessary to have opened in future steps.  If the analysis has completed and you do not intend on running more simulations the workers may be terminated in order to save money.  As long as the OpenStudio-Server instance is running the results can be downloaded.

Navigate to your local PAT projects directory and open your current PAT project.  Once inside navigate to 
```
./pat_projects/<PATProjectName>/clusters/xx(x)_cpu_xxxxgb_hdd_x_dollar_per_hour/
```
in order to find your `ec2_server_key.pem` file.  This will allow you to connect to the AWS OpenStudio-Server and download the results.

Copy the `ec2_server_key.pem` to your local Docker container in `/home/osdev/` or any other directory of your preference.

(To do this copy the `ec2_server_key.pem` file to `C:\Users\<yourUserName>`.  Then once inside your Docker container enter the command `cp ~/windows-host/ec2_server_key.pem .` )

Change the permissions of your key from 0755 to either 400 or 600 so that it is not too open.

`chmod 400 ec2_server_key.pem`

Note: if using the spreadsheet method found here https://goo.gl/Ynnm6x then the `ec2_server_key.pem` file will be found in your `OpenStudio-analysis-spreadsheet` repository and you can continue the rest of the steps from this repository without having to change the permissions of the key.

To connect to the AWS OpenStudio-Server use the following command in your Docker container in the directory that contains your `ec2_server_key.pem`.

`ssh -i ec2_server_key.pem ubuntu@ec2-xx-xxx-xxx-xx.compute-1.amazonaws.com` Where the `ec2-xx-xxx-xxx-xx` part of the command can be found in the URL of the AWS console tab in your web browser.

IMAGE ec2Address.png

IMAGE connectAWS2.png 

When prompted with `Are you sure you want to continue connecting (yes/no)?` type `yes`.

IMAGE connectAWS.png

You are now in the OpenStudio-Server and should see `ubuntu@ip-xx-xx-xx-xx:-$` as your command line.

Type `docker ps` in the command line to list the Container ID Names running on the OpenStudio-Server and look for the one called `osserver_web.1.xxxxxxxxxxxxxxxxxxxxxxxxx`.  There will be a 12 digit alphanumerical container ID that you will need right above `osserver_web.1.xxxxxxxxxxxxxxxxxxxxxxxxx`. Copy this ID into your buffer.

IMAGE webContainerID.png

Use the container ID to enter the web server with the following command.

`docker exec -it <containerID> /bin/bash`

Your command line should be something like `root@xxxxxxxxxxxx:/opt/openstudio/server#`

Clone this repository into the `/opt/openstudio/server` directory that you should currently be in to have access to the `gather_results.rb` script and the required `Gemfile`

`git clone https://github.com/canmet-energy/btap_gather_results.git`

You will be prompted to enter your Github username and password as this is a private repository in canmet-energy.  If you do not have permission to access this repository contact your supervisor to give you the required permission.

Once the `btap_gather_results` repository finishes cloning enter it and run `bundle install`

`cd btap_gather_results && bundle install`

*optional step to install nano to read and make changes to files if modifying files: `sudo apt-get update && sudo apt-get install nano`*

Inside of `btap_gather_results' enter the following command to execute the script

`bundle exec ruby gather_results.rb -a <analysisID>`
  
The analysis ID can be found by clicking `View Analysis` on the AWS console dashboard in your web browser.

`http://ec2-XXX-XXX-XXX-XXX.compute-1.amazonaws.com/analyses/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX`

where `XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX` is the analysis ID.



IMAGE analysisID.png

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


