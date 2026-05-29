fx_version 'cerulean'
game 'gta5'

name 'rc_coin_shop'
description 'ESX coin shop - buy ox_inventory items with coins, admin coin management'
author 'codejunkie'
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
    'server/main.lua'
}

dependencies {
    'es_extended',
    'ox_lib',
    'ox_inventory',
    'oxmysql'
}
