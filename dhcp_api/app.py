from flask import Flask, json, jsonify, request
import subprocess
import os
import sys

app = Flask(__name__)
#basically what this does is it looks at the argumens given to the python3 bash command when you use it on
#the file, which will always be at least one because the file name is an argument, and then it checks to see
#if there are more than one, if there are, is the second one an integer? If it is, make it the port for the api.
#otherwise run the api on port 8080
if len(sys.argv) > 1:
    try:
        int(sys.argv[1])
        PORT = sys.argv[1]
    except:
        PORT = 8080
else:
    PORT = 8080

#serverName = 'builder-00.ofa.iol.unh.edu:' + str(PORT)
#app.config['SERVER_NAME'] = serverName 

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
    query = subprocess.run(['bash', 'scripts/restart_dhcp.sh'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    #if the command returns without error
    if query.returncode == 0:
        return jsonify({"status": 200, "message": "dhcp4 was restarted successfully"}), 200
    else:
        return jsonify({"status": 500, "message": "internal server error"}), 500

#--------------------------------
#        restart dhcp6
#--------------------------------
@app.route('/restartDhcp6Service', methods=["POST"])
def restartdhcp6():
    query = subprocess.run(['bash', 'scripts/restart_dhcp6.sh'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
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
    query = subprocess.run(['bash', 'scripts/status_dhcp4.sh'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    query2 = subprocess.run(['bash', 'scripts/status_dhcp6.sh'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    
    #if the command returns without error
    #includes both codes 0 and 3 because with a "systemctl status" command a code 0 means the service
    #is running and a code 3 means it is inactive
    if query.returncode == 0 or query.returncode == 3:
        #formatting for dhcp4 bash command output
        dhcp4String = str(query.stdout)
        dhcp4Arr = dhcp4String.split('\\n')
        dhcp4Output = dhcp4Arr[2].strip()
        dhcp4Output = dhcp4Output.replace("Active", "Status", 1)
        
        #Formatting for dhcp6 bash command output
        dhcp6String = str(query2.stdout)
        dhcp6Arr = dhcp6String.split('\\n')
        dhcp6Output = dhcp6Arr[2].strip()
        dhcp6Output = dhcp6Output.replace("Active", "Status", 1)
        return jsonify({"status": 200, "message": {"dhcp4Status": dhcp4Output, "dhcp6Status": dhcp6Output}}), 200
    else:
        return jsonify({"status": 500, "message": "internal server error"}), 500

#------------------------------
#     Rebuild DHCP Config
#------------------------------
@app.route('/rebuildDhcp', methods=["POST"])
def rebuildDhcp():
    #creates a list of file names from the given path
    fileNameList = os.listdir('/var/lib/tftpboot/hosts.d/')
    fileNameString = ""
    for file in fileNameList:
        fileNameString = fileNameString + "/var/lib/tftpboot/hosts.d/" + file + " "
    query = subprocess.run(["sudo", "bash", "scripts/rebuild_dhcp.sh", fileNameString], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if query.returncode == 0:
        return jsonify({"status": 200, "message": "Rebuilt DHCP"}), 200
    else:
        print(query.stderr)
        return jsonify({"status": 500, "message": "Internal server error"}), 500

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
        query = subprocess.run(["bash", "scripts/rm_dhcp_file.sh", ""+fileName], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
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
    app.run(debug=True, port=PORT)
