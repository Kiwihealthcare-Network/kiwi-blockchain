#!/bin/bash

echo "clean source ========================="
rm -rf ./build_scripts/build
rm -rf ./build_scripts/dist
rm -rf ./build_scripts/final_installer
cd chia-blockchain-gui
git clean -fdx
cd ../

echo "venv & install ========================="
python3 -m venv venv
. ./venv/bin/activate

python3 -m pip install --upgrade pip
python3 -m pip install wheel
python3 -m pip install --extra-index-url https://pypi.chia.net/simple/ miniupnpc==2.1
python3 -m pip install -e . --extra-index-url https://pypi.chia.net/simple/

echo "Installing npm and electron packagers"
npm install electron-installer-dmg -g
npm install electron-packager -g
npm install electron/electron-osx-sign -g
npm install notarize-cli -g

echo "cd build_scripts & pyinstaller ========================="
cd build_scripts
mkdir dist

echo "Create executables with pyinstaller"
pip install pyinstaller==4.5
python3 -m pip install setuptools_scm

#SPEC_FILE=$(python -c 'import chia; print(chia.PYINSTALLER_SPEC_PATH)')
SPEC_FILE=$(python3 -c 'import chia; print(chia.PYINSTALLER_SPEC_PATH)')
pyinstaller --log-level=INFO "$SPEC_FILE"
LAST_EXIT_CODE=$?
if [ "$LAST_EXIT_CODE" -ne 0 ]; then
	echo >&2 "pyinstaller failed!"
	exit $LAST_EXIT_CODE
fi

deactivate

# The environment variable KIWI_INSTALLER_VERSION needs to be defined.
# If the env variable NOTARIZE and the username and password variables are
# set, this will attempt to Notarize the signed DMG.

#KIWI_INSTALLER_VERSION=$(python installer-version.py)
KIWI_INSTALLER_VERSION=$(python3 installer-version.py)
if [ ! "$KIWI_INSTALLER_VERSION" ]; then
	echo "WARNING: No environment variable KIWI_INSTALLER_VERSION set. Using 0.0.0."
	KIWI_INSTALLER_VERSION="0.0.0"
fi
echo "Kiwi Installer Version is: $KIWI_INSTALLER_VERSION"

echo "cp daemon ========================="
cp -r dist/daemon ../chia-blockchain-gui
cd .. || exit
cd chia-blockchain-gui || exit

echo "npm build"
npm install
npm audit fix
npm run build
LAST_EXIT_CODE=$?
if [ "$LAST_EXIT_CODE" -ne 0 ]; then
	echo >&2 "npm run build failed!"
	exit $LAST_EXIT_CODE
fi

electron-packager . Kiwi --asar.unpack="**/daemon/**" --platform=darwin \
--icon=src/assets/img/Chia.icns --overwrite --app-bundle-id=net.chia.blockchain \
--appVersion=$KIWI_INSTALLER_VERSION
LAST_EXIT_CODE=$?
if [ "$LAST_EXIT_CODE" -ne 0 ]; then
	echo >&2 "electron-packager failed!"
	exit $LAST_EXIT_CODE
fi

if [ "$NOTARIZE" ]; then
  electron-osx-sign Kiwi-darwin-x64/Kiwi.app --platform=darwin \
  --hardened-runtime=true --provisioning-profile=chiablockchain.provisionprofile \
  --entitlements=entitlements.mac.plist --entitlements-inherit=entitlements.mac.plist \
  --no-gatekeeper-assess
fi
LAST_EXIT_CODE=$?
if [ "$LAST_EXIT_CODE" -ne 0 ]; then
	echo >&2 "electron-osx-sign failed!"
	exit $LAST_EXIT_CODE
fi

mv Kiwi-darwin-x64 ../build_scripts/dist/
cd ../build_scripts || exit

DMG_NAME="Kiwi-$KIWI_INSTALLER_VERSION.dmg"
echo "Create $DMG_NAME"
mkdir final_installer
electron-installer-dmg dist/Kiwi-darwin-x64/Kiwi.app Kiwi-$KIWI_INSTALLER_VERSION \
--overwrite --out final_installer
LAST_EXIT_CODE=$?
if [ "$LAST_EXIT_CODE" -ne 0 ]; then
	echo >&2 "electron-installer-dmg failed!"
	exit $LAST_EXIT_CODE
fi

if [ "$NOTARIZE" ]; then
	echo "Notarize $DMG_NAME on ci"
	cd final_installer || exit
  notarize-cli --file=$DMG_NAME --bundle-id net.chia.blockchain \
	--username "$APPLE_NOTARIZE_USERNAME" --password "$APPLE_NOTARIZE_PASSWORD"
  echo "Notarization step complete"
else
	echo "Not on ci or no secrets so skipping Notarize"
fi

# Notes on how to manually notarize
#
# Ask for username and password. password should be an app specific password.
# Generate app specific password https://support.apple.com/en-us/HT204397
# xcrun altool --notarize-app -f Kiwi-0.1.X.dmg --primary-bundle-id net.chia.blockchain -u username -p password
# xcrun altool --notarize-app; -should return REQUEST-ID, use it in next command
#
# Wait until following command return a success message".
# watch -n 20 'xcrun altool --notarization-info  {REQUEST-ID} -u username -p password'.
# It can take a while, run it every few minutes.
#
# Once that is successful, execute the following command":
# xcrun stapler staple Kiwi-0.1.X.dmg
#
# Validate DMG:
# xcrun stapler validate Kiwi-0.1.X.dmg
