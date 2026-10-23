# Device verification

These are hands-on checks, not a promise that every Android phone or Windows PC behaves the same way.

## Confirmed

- A Pixel 8 Pro transferred files with Nearby Drop over local Wi-Fi. Mac-generated and Android-generated QR flows both completed.
- One Windows PC using Google Quick Share sent files to the Mac and received files from it. The successful checks used a development build after the Windows endpoint-name fix; the packaged release was not separately tested on that PC.

## Not confirmed in the latest round

- USB MTP browsing, upload, and download were not completed as part of the latest logged device checks. The app supports MTP; unlock the phone and choose **File transfer / Android Auto** before testing it.
- Discovery through an LTE phone hotspot was not verified because the mobile connection was unstable.
- Other Windows PCs and Android models were not tested.
