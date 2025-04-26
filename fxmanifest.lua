fx_version 'cerulean'
game 'gta5'

shared_script '@es_extended/imports.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/esx_vehicle_reconnect.lua'
}

client_scripts {
    'client/esx_vehicle_reconnect.lua'
}

dependencies {
    'es_extended',
    'oxmysql'
}