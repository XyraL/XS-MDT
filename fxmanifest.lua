fx_version 'cerulean'
game 'gta5'

name 'XS-MDT'
description 'Multi-department MDT (Police / EMS / Fire) with CAD integration for QBox'
version '2.1.0'
author 'XyraL'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

dependencies {
    'ox_lib',
    'qbx_core',
    'oxmysql',
}

client_scripts {
    'client/main.lua',
    'client/cad.lua',
    'client/blips.lua',
    'client/dispatch.lua',
    'client/sounds.lua',
    'client/target.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/integrations.lua',
    'server/evidence-bridge.lua',
    'server/dispatch.lua',
    'server/officers.lua',
    'server/civilians.lua',
    'server/vehicles.lua',
    'server/licences.lua',
    'server/warrants.lua',
    'server/bolos.lua',
    'server/records.lua',
    'server/penal.lua',
    'server/incidents.lua',
    'server/cad.lua',
    'server/bulletins.lua',
    'server/bodycam.lua',
    'server/target.lua',
    'server/shiftlog.lua',
    'server/ems.lua',
    'server/fire.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/style.css',
    'html/js/app.js',
    'html/js/panels/officer.js',
    'html/js/panels/civilians.js',
    'html/js/panels/vehicles.js',
    'html/js/panels/warrants.js',
    'html/js/panels/bolos.js',
    'html/js/panels/records.js',
    'html/js/panels/penal.js',
    'html/js/panels/incidents.js',
    'html/js/panels/cad.js',
    'html/js/panels/bulletins.js',
    'html/js/panels/quickdispatch.js',
    'html/js/panels/mugshots.js',
    'html/js/panels/callhistory.js',
    'html/js/panels/shiftlog.js',
    'html/js/panels/map.js',
    -- Leaflet is vendored (BSD-2) — NUI has no reliable internet, so no CDN.
    'html/vendor/leaflet/leaflet.js',
    'html/vendor/leaflet/leaflet.css',
    'html/vendor/leaflet/images/*.png',
    'html/vendor/leaflet/LICENSE.txt',
    -- Map tile pyramid, built by tools/build-map-tiles.js. Flat {z}_{x}_{y}
    -- filenames in one directory: a single-level glob is the form FiveM
    -- actually expands — nested ** silently shipped nothing and left the map
    -- blank.
    'html/assets/maps/tiles/*.webp',
    'html/assets/maps/OULSEN-LICENSE.txt',
    'html/js/panels/ems.js',
    'html/js/panels/fire.js',
    'html/js/components/namesearch.js',
}

lua54 'yes'
