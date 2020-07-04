# User Management
## Description
GFL's User Management plugin that handles Members, Supporters, and VIPs.

## Requirements
* [GFL Core](https://github.com/GFLClan/SM-Core) - The core of the GFL SourceMod plugins and includes useful natives for logging purposes.
* [REST In Pawn](https://forums.alliedmods.net/showthread.php?t=298024) - A plugin that makes it easy to send HTTP requests to REST APIs.

## ConVars
* `sm_gflum_url` => The hostname of the web server that serves the REST API (default `"something.com"`).
* `sm_gflum_endpoint` => The endpoint/file name (default `index.php`).
* `sm_gflum_token` => The authorization token to set when sending HTTP requests (default `""`).
* `sm_gflum_debug` => Whether to enable verbose debugging within the plugin (default `0`).

## Credits
* [Christian Deacon](https://www.linkedin.com/in/christian-deacon-902042186/) - Creator.
* [Nick](https://github.com/NVedsted) - Rewrote plugin to improve functionality.
* [Blueberry](https://github.com/Blueberryy) - Russian translation file.