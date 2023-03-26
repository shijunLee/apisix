local host_pattern = [[^http(s)?:\/\/([a-zA-Z0-9-_.]+:.+\@)?[a-zA-Z0-9-_.:]+$]]
local prefix_pattern = [[^[\/a-zA-Z0-9-_.]+$]]


return {
    type = 'object',
    properties = {
        http_host = {
            type = 'array',
            minItems = 1,
            items = {
                type = 'string',
                pattern = host_pattern,
                minLength = 2,
                maxLength = 100,
            },
        },
        fetch_interval = {type = 'integer', minimum = 1, default = 30},
        prefix = {
            type = 'string',
            pattern = prefix_pattern,
            maxLength = 100,
            default = '/micro/registry/'
        },
        weight = {type = 'integer', minimum = 1, default = 100},
        timeout = { type = 'integer', minimum =1, default =30   },
        tls = {
            type = 'object',
            properties = {
                verify = {type = 'boolean', default = false},
                cert = {type = 'string'},
                key = {type = 'string'},
                sni = {type = 'string'},
            },
        },
        user ={ type = 'string'},
        password ={ type = 'string'},
    },
    required = {'host'}
}
 