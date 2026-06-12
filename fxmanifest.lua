fx_version 'cerulean'
game 'gta5'

name 'rc_coin_shop'
description 'Coin shop for ESX & QBCore - buy ox_inventory items with coins, admin coin management'
author 'sudo-umair'
version '1.0.0'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/server.lua',
    'server/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/logo.png'
}

dependencies {
    'ox_lib',
    'ox_inventory',
    'oxmysql'
}
