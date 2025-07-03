# MECM-Buddy
MECM Buddy helps you download, update, and deploy SCCM apps automatically. It also helps with bulk packaging installers into .intuneWin files when deploying to the cloud. 

# Introduction
I'm super excited to finally be sharing MECM Buddy with the world! This project aims to simplify the downloading, packaging, script running, and uploading apps to Microsoft Endpoint Configuration Manager (MECM) / System Center Configuration Manager (SCCM). It allows the creation and importing of recipes and simplifies deployments into one big process instead of several modules in MECM. I also added a packager for .intuneWin files which will help when you have a bunch of files you need to quickly package before they go to Intune. 

# Dependencies
It relies on a few PowerShell module dependencies, like Evergreen (GitHub), ConfigurationManager (Microsoft), and having a local install of MECM and an internet connection. If you want to use VirusTotal, you need an API key. Additionally, you need to have Malwarebytes Nebula installed for that function to work. Being an Admin on the machine is required because you need to install PowerShell modules. I also use and recommend PowerShell App Deployment Toolkit to make the user install experience better. PSTK is needed if you are going to package the installers for Intune. It just streamlines things.  

# Notice
I'm a college student who is just getting started, so if you would like to contribute, please do! If you want to contribute, you can add pull requests. Also, pay attention to the licensing. You need to credit Sophie Carlson (me) if you use my code and provide a link back to this project!

Also, head over to my site for more information and higher detail documentation at: socarlson (dot) com

Made with love by a human. No Ai was used in the making of this software. 
