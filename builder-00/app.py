from flask import Flask, json, jsonify, request
import subprocess
import os
import sys

app = Flask(__name__)
#basically what this does is it looks at the argumens given to the python3 bash command when you use it on
#the file, which will always be at least one because the file name is an argument, and then it checks to see
#if there are more than one, if there are, is the second one an integer?
if len(sys.argv) > 1:
    try:
        int(sys.argv[1])
    #if the argument is not an integer
    except:
        #found how to raise errors from https://stackoverflow.com/questions/2052390/manually-raising-throwing-an-exception-in-python
        raise ValueError("Invalid port. Port must be in integer greater than 0.")

    #if the argument is an integer and is greater than 0
    if int(sys.argv[1]) > 0:
        PORT = sys.argv[1]
    else:
        raise ValueError("Invalid port. Port must be in integer greater than 0.")
        
#if the command doesn't have an additional argument
else:
    raise ReferenceError("Port required. Command should be, \"python3 app.py <PORT>\"")

#serverName = 'builder-00.ofa.iol.unh.edu:' + str(PORT)
#app.config['SERVER_NAME'] = serverName 

dhcpd_scripts_variable = "dhcpd_scripts"

#--------------------------------
#    get a list of file names
#--------------------------------
@app.route('/hosts.d', methods=["GET"])
def getFileNames():
    #gets file names from specified path
    #docs.python.org/3/library/os.html
    fileNameList = os.listdir('/var/lib/tftpboot/hosts.d/')
    return jsonify({"fileNames": fileNameList}), 200

#--------------------------------
#        restart dhcp4
#--------------------------------
@app.route('/restartDhcp4Service', methods=["POST"])
def restartDhcp():
    query = subprocess.run(['sudo', os.getcwd() + dhcpd_scripts_variable +  '/restart_dhcp.sh'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    #if the command returns without error
    if query.returncode == 0:
        return jsonify({"status": 200, "message": "Dhcp4 restarted successfully"}), 200
    else:
        return jsonify({"status": 500, "message": "There was an error restarting Dhcp4"}), 500

#--------------------------------
#        restart dhcp6
#--------------------------------
@app.route('/restartDhcp6Service', methods=["POST"])
def restartdhcp6():
    query = subprocess.run(['sudo', os.getcwd() + dhcpd_scripts_variable + '/restart_dhcp6.sh'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if query.returncode == 0:
        return jsonify({"status": 200, "message": "dhcp6 was restarted successfully"}), 200
    else:
        return jsonify({"status": 500, "message": "internal server error"}), 500

#--------------------------------
#       check dhcp status
#--------------------------------
@app.route('/checkDhcpStatus', methods=["POST"])
def checkDhcp():
    #bash commands to check status of both dhcp4 and dhcp6
    query = subprocess.run(['sudo', os.getcwd() + dhcpd_scripts_variable + '/status_dhcp4.sh'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    query2 = subprocess.run(['sudo', os.getcwd() + dhcpd_scripts_variable + '/status_dhcp6.sh'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    
    #if the command returns without error
    #includes both codes 0 and 3 because with a "systemctl status" command a code 0 means the service
    #is running and a code 3 means it is inactive
    dhcp4_status_exists = False
    dhcp6_status_exists = False

    if query.returncode == 0 or query.returncode == 3:
        dhcp4_status_exists = True

    if query2.returncode == 0 or query2.returncode == 3:
        dhcp6_status_exists = True

    #function to format the outputs of bash commands
    def formatDhcp(input):
        dhcpString = str(input)
        dhcpArr = dhcpString.split('\\n')
        dhcpOutput = dhcpArr[2].strip()
        dhcpOutput = dhcpOutput.replace("Active", "Status", 1)
        return dhcpOutput
    
    #if both dchp4 and dhcp6 have a status 
    if dhcp4_status_exists and dhcp6_status_exists:
        return jsonify({"status": 200, "message": {"dhcp4Status": formatDhcp(query.stdout), "dhcp6Status": formatDhcp(query2.stdout)}}), 200
    #if only dhcp4 has a status
    elif dhcp4_status_exists and dhcp6_status_exists != True:
        return jsonify({"status": 206, "message": {"dhcp4Status": formatDhcp(query.stdout), "dhcp6Status": "Unknown"}}), 206
    #if only dhcp6 has a status
    elif dhcp6_status_exists and dhcp4_status_exists != True:
        return jsonify({"status": 206, "message": {"dhcp4Status": "Unknown", "dhcp6Status": formatDhcp(query2.stdout)}}), 206
    #if neither status can be found
    else:
        return jsonify({"status": 500, "message": "Internal server error. Could not find status of dhcp4 or dhcp6."}), 500

#------------------------------
#     Rebuild DHCP Config
#------------------------------
@app.route('/rebuildDhcp', methods=["POST"])
def rebuildDhcp():
    #essentially, this try statement says if we found the node files, continue, if not, throw an error
    try:
        #creates a list of file names from the given path
        fileNameList = os.listdir('/var/lib/tftpboot/hosts.d/')
    except:
        return jsonify({"status": 502, "message": "Unable to find node configuration files"}), 502
    #bash command resets the config file with a new template
    query = subprocess.run(["sudo", os.getcwd() + dhcpd_scripts_variable + "/reset_dhcpd_config.sh"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    #if the script ran without error
    if query.returncode == 0:
        for node in fileNameList:
            query2 = subprocess.run(["bash", os.getcwd() + dhcpd_scripts_variable + "/rebuild_dhcp.sh", ""+node], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return jsonify({"status": 200, "message": "Rebuilt dhcpd configuration successfully"}), 200
    else:
        return jsonify({"status": 500, "message": "Error rebuilding the dhcpd configuration file"}), 500
    
    

#------------------------------
#      delete a node file
#------------------------------
@app.route('/hosts.d/<fileName>', methods=["DELETE"])
def deleteAFile(fileName):
    #creates a list of file names from the given path and then uses the .count method to see if the given
    #parameter matches one of the file names
    fileNameList = os.listdir('/var/lib/tftpboot/hosts.d/')
    fileNameCheck = fileNameList.count(fileName)
    if fileNameCheck == 1:
        query = subprocess.run(["sudo", os.getcwd() + dhcpd_scripts_variable + "/rm_dhcp_file.sh", ""+fileName], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        #if there were no errors
        if query.returncode == 0:
            return jsonify({"status": 200, "message": "File was deleted"}), 200
        #if the bash command encountered an error
        else:
            print(query.stderr)
            return jsonify({"status": 500, "message": "Internal server error"}), 500
    else:
        return jsonify({"status":404, "message": "File was not found"}), 404

if __name__ == "__main__":
    app.run(port=PORT)
