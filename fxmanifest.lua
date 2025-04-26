fx_version 'cerulean'
game 'gta5'

shared_script '@es_extended/imports.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/vehicle_manager.lua',
    'server/server.lua'
}

client_scripts {
    'client/client.lua'
}

dependencies {
    'es_extended',
    'oxmysql'
}
