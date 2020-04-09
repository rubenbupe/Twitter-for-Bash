source tui_utils.sh
source conf.twbs

#Al ejecutar el script, establece ciertas variables dependiendo del SO, macOS o Linux.
case $(uname) in
  Darwin|*BSD|CYGWIN*)
    schar="\033"
    twpython=venvpm/bin/python
    ;;
  *)
    schar="\e"
    twpython=venv/bin/python
    ;;
esac

# Comprueba que exista el directorio de logs, si no lo crea.
check_files() {

  if [ ! -d logs ]; then
    mkdir logs
  fi

}

# Comprueba que están disponibles los comandos necesarios y si no da error
check_commands(){
  local do_exit=0

  if ! exist_command jq
  then
    info 'Intentando instalar el comando "jq"...'
    if exist_command apt ; then
        sudo apt install jq
    elif exist_command yum ; then
        sudo yum install jq
    elif exist_command brew ; then
        sudo brew install jq
    fi

    if ! exist_command jq ; then
        error 'Falta el comando "jq". Por favor, ejecuta apt|yum|brew install jq, como sudo. ' 1>&2
        do_exit=1
    else
        info "Instalación completada con éxito."
    fi
  fi

    if ! exist_command python3
  then
    info 'Intentando instalar el comando "python3"...'
    if exist_command apt ; then
        sudo apt install python3
    elif exist_command yum ; then
        sudo yum install python3
    elif exist_command brew ; then
        sudo brew install python3
    fi

    if ! exist_command python3 ; then
        error 'Falta el comando "python3". Por favor, ejecuta apt|yum|brew install python3, como sudo. ' 1>&2
        do_exit=1
    else
        info "Instalación completada con éxito."
    fi
  fi

  if [ $do_exit = 1 ]; then
    exit 1
  fi
}

# Comprueba si existe un comando
exist_command() {
  type "$1" > /dev/null 2>&1
}

# Llama al programa de python que hace las peticiones a la API de Twitter
make_request(){
    check_files
    check_commands
    echo $( echo "$( cat )" | $twpython api.py $1 $2 $3 $4 )
}

# Refresca el timeline
#Uso: refresh_timeline max_id
refresh_timeline(){ 
    local count=$TL_TWEETS
    local tweet_mode="tweet_mode extended"

    # Si el usuario usa la opcion -m, el parametro max_id se agraga a la petición, la cual será respondida con tweets más antiguos
    if [ $# -eq 1 ]; then  
        local max_id="max_id $1"
    else
        local max_id=""
    fi

    local parameters="count $count
        $tweet_mode
        $max_id"
    
    local response="$(echo "$parameters" |
                    make_request GET https://api.twitter.com/1.1/statuses/home_timeline.json)"
    
    if echo $response | jq -e ". | objects | has(\"errors\")"  > /dev/null ; then
        error "No se ha podido actualizar el timeline"
        exit 1
    fi
    echo "$response" > logs/tl.twbs
    print_timeline
}

# Decuelve la id de un tweet en base al log en el que está y su índice
#Uso: get_tweet_id_by_index tl_file index  -> | retweet/favorite
get_tweet_id_by_index(){
    local len=$( jq ". | length - 1" $1 )

    if [ $2 -lt 0 -o $2 -gt $len ]; then # Comprueba que el índice esté en rango
        error "Índice fuera de rango"
        exit 1
    fi

    if [ "$1" = "logs/tweet_search.twbs" ]; then # Depende del archivo utiliza un comando u otro
        echo $( jq -r ".statuses[$2].id_str" $1 )
    else
        echo $( jq -r ".[$2].id_str" $1 )
    fi

}

# Decuelve el nombre de usuario de un tweet o usuario (busquedas) en base al log en el que está y su índice
# Uso: get_tweet_user_by_index tl_file index
get_tweet_user_by_index(){

    local len=$( jq ". | length - 1" $1 )

    if [ $2 -lt 0 -o $2 -gt $len ]; then
        error "Índice fuera de rango"
        exit 1
    fi

    if [ "$1" = "logs/user_search.twbs" ]; then
        echo $( jq -r ".[$2].screen_name" $1 )
    elif [ "$1" = "logs/tweet_search.twbs" ]; then
        echo $( jq -r ".statuses[$2].user.screen_name" $1 )
    else
        echo $( jq -r ".[$2].user.screen_name" $1 )
    fi
}

#Funciona igual que el anterior pero en caso de RTs, devuelve el nombre de usuario que twitteo el tweet original
# Uso: get_tweet_user_by_index tl_file index
get_original_tweet_user_by_index(){

    local len=$( jq ". | length - 1" $1 )

    if [ $2 -lt 0 -o $2 -gt $len ]; then
        error "Índice fuera de rango"
        exit 1
    fi

    if [ "$1" = "logs/tweet_search.twbs" ]; then
        local tweet=$( jq -r ".statuses[$2]" $1 )
    else
        local tweet=$( jq -r ".[$2]" $1 )
    fi

    if echo $tweet | jq -e ". | has(\"retweeted_status\")" > /dev/null ; then
        echo $( echo $tweet | jq -r ".retweeted_status.user.screen_name" )
    else
        echo $( echo $tweet | jq -r ".user.screen_name" )
    fi


}

# Hace la llamada a la API para dar o quitar retweet
# Uso: echo tweet_id | call_retweet retweet/unretweet
call_retweet(){
    local tweet_id=$( cat )
    
    local response="$(make_request POST https://api.twitter.com/1.1/statuses/$1/$tweet_id.json)"
    if echo $response | jq -e ". | has(\"errors\")"  > /dev/null ; then
        echo false
    else
        echo true
    fi
}

# Llama a la función anterior para dar RT
retweet(){
    echo $( echo $( cat ) | call_retweet "retweet" )
}

# Igual que la función anterior pero para quitar un RT
unretweet(){
    echo $( echo $( cat ) | call_retweet "unretweet" )
}

# Llama a la API para dar o quitar de favoritos un tweet
# Uso: echo tweet_id | call_favorite create/destroy
call_favorite(){
    local tweet_id=$( cat )

    local parameters="id $tweet_id"
    
    local response="$(echo "$parameters" | make_request POST https://api.twitter.com/1.1/favorites/$1.json)"
    if echo $response | jq -e ". | has(\"errors\")"  > /dev/null ; then
        echo false
    else
        echo true
    fi
}

# Llama a la función anterior para dar favs
favorite(){
    echo $( echo $( cat ) | call_favorite "create" )
}

# Igual que la función anterior pero para quitar un favorito
unfavorite(){
    echo $( echo $( cat ) | call_favorite "destroy" )
}

# Función que se encarga de llamar a dar retweet o quitar retweet en base al índice y el archivo en el que esté el tweet
# Uso: retweet_by_index logs/tl.twbs 2
retweet_by_index(){
    local tweet_id=$( get_tweet_id_by_index $1 $2 )
    if jq -e ".[$2].retweeted" $1 > /dev/null ; then  # Si ya se ha retwitteado, lo desretwittea
        local result=$( echo $tweet_id | unretweet )
        if $result ; then 
            jq -r ".[$2].retweeted = false" $1 > $1.tmp && mv $1.tmp $1
            info "Se ha desretwitteado el tweet con id $tweet_id"
        else
            error "No se ha podido desretwittear el tweet con id $tweet_id"
            exit 1
        fi
    else  # Si no lo retwittea
        local result=$( echo $tweet_id | retweet )
        if $result ; then 
            jq -r ".[$2].retweeted = true" $1 > $1.tmp && mv $1.tmp $1
            info "Se ha retwitteado el tweet con id $tweet_id"
        else
            error "No se ha podido retwittear el tweet con id $tweet_id"
            exit 1
        fi
    fi
}

# Función que se encarga de llamar a dar favs o quitar favs en base al índice y el archivo en el que esté el tweet
favorite_by_index(){
    local tweet_id=$( get_tweet_id_by_index $1 $2 )
    if jq -e ".[$2].favorited" $1 > /dev/null ; then  # Si ya se ha dado like, lo quita
        local result=$( echo $tweet_id | unfavorite )
        if $result ; then 
            jq -r ".[$2].favorited = false" $1 > $1.tmp && mv $1.tmp $1            
            info "Se ha quitado de favoritos el tweet con id $tweet_id"
        else
            error "No se ha podido quitar de favoritos el tweet con id $tweet_id"
            exit 1
        fi
    else  # Si no se lo da
        local result=$( echo $tweet_id | favorite )
        if $result ; then 
            jq -r ".[$2].favorited = true" $1 > $1.tmp && mv $1.tmp $1
            info "Se ha añadido a favoritos el tweet con id $tweet_id"
        else
            error "No se ha podido añadir a favoritos el tweet con id $tweet_id"
            exit 1
        fi
    fi
}

# Función que twittea
# Uso: echo "Nuevo status" | update_status media_ids [tl_tweet_responder n_tweet_responder]
update_status(){
    local status="$( cat )"
    local media=$1

    local in_reply_to_status_id="" #Si recibe tres parámetros, los dos últimos indican el tweet al que responden. Se agrega a la petición
    if [ $# -eq 3 ]; then
        in_reply_to_status_id="in_reply_to_status_id $( get_tweet_id_by_index $2 $3 )"
        local user=$( get_original_tweet_user_by_index $2 $3 )
        status="@$user $status"
    fi

    # Solo deja twittear si son menos de 240 caracteres, incluyendo la mención que se añade automaticamente para las respuestas
    if [ $( echo -n "$status" | wc -c ) -gt 240 ]; then
        error "El tweet no puede tener más de 240 caracteres"
        exit 1
    fi
    
    local parameters="status $status 
    $in_reply_to_status_id
    media_ids $media"

    local response="$(echo "$parameters" | make_request POST https://api.twitter.com/1.1/statuses/update.json )"
    if echo $response | jq -e ". | has(\"errors\")"  > /dev/null ; then
        error "No se ha podido twittear el siguiente tweet: \n$status"
        exit 1
    fi
    info "Se ha twitteado con éxito."
}

# Llama a la API para ver los favoritos y los tweets de un usuario
# Uso: get_user_profile -f/-t @user_name    o    get_user_profile -f/-t tl_file index
get_user_profile(){
    if [ $# -eq 3 ]; then
        local user_name=$( get_tweet_user_by_index $2 $3 )
    else
        local user_name=$2
    fi
    local count=$USER_TWEETS
    local trim_user="trim_user 0"
    local tweet_mode="tweet_mode extended"

    local parameters="screen_name $user_name
        count $count
        $tweet_mode"

    local tweets="$(echo "$parameters" | make_request GET https://api.twitter.com/1.1/statuses/user_timeline.json)"
    local favs="$(echo "$parameters" | make_request GET https://api.twitter.com/1.1/favorites/list.json)"

    if echo $tweets | jq -e ". | objects | has(\"errors\")"  > /dev/null ; then
        error "No se han podido conseguir los tweets de $user_name"
        exit 1
    fi
    if echo $favs | jq -e ". | objects | has(\"errors\")"  > /dev/null ; then
        error "No se han podido conseguir los favoritos de $user_name"
        exit 1
    fi

    echo $tweets > logs/user_tl.twbs
    echo $favs > logs/user_favs.twbs

    print_user_profile $1
 
}

# Llama a la API para seguir a un usuario
# Uso: follow_user user
follow_user(){
    local user=$1

    local parameters="screen_name $user"

    local response="$( echo "$parameters" | make_request POST https://api.twitter.com/1.1/friendships/create.json )"

    if echo $response | jq -e ". | objects | has(\"errors\")"  > /dev/null ; then
        error "No se ha podido seguir al usuario @$user"
        exit 1
    fi

    info "Ahora sigues a @$user"
}

# Llama a la API para dejar de seguir a un usuario
# Uso: unfollow_user user
unfollow_user(){
    local user=$1

    local parameters="screen_name $user"

    local response="$( echo "$parameters" | make_request POST https://api.twitter.com/1.1/friendships/destroy.json )"
    if echo $response | jq -e ". | objects | has(\"errors\")"  > /dev/null ; then
        error "No se ha podido dejar de seguir al usuario @$user"
        exit 1
    fi

    info "Ahora ya no sigues a @$user"
}

# Función que llama a follow_user o unfollow_user dependiendo de si ya se sigue o no al usuario
call_follow_user(){

    if [ $# -eq 0 ]; then
        local user=$( cat logs/user_tl.twbs | jq -r ".[0].user.screen_name") 
    elif [ $# -eq 1 ]; then
        local user=$( echo $1 | tr -d "@" )
    else
        local user=$( get_tweet_user_by_index $1 $2 )
    fi

    # Comprueba que no te siguas a ti mismo
    if [ "$MY_SCREEN_NAME" = "$user" ]; then
        error "No te puedes seguir a ti mismo"
        exit 1
    fi

    # Pide los detalles del usuario a seguir a la API para saber si ya lo sigue. En tal caso lo deja de seguir
    local user_details=$( echo "screen_name $user" | make_request GET https://api.twitter.com/1.1/users/show.json)
    if echo $user_details | jq -e ". | objects | has(\"errors\")"  > /dev/null ; then
        error "No se ha podido comprobar el estado de seguimiento del usuario @$user"
        exit 1
    fi

    local following=$( echo $user_details | jq -e ".following" )

    if $following ; then
        unfollow_user "$user"
    else
        follow_user "$user"
    fi

    # Una vez seguido, guarda en el log que el usuario ha usado para seguirlo el nuevo estado de seguimiento
    if [ $# -eq 0 ]; then
        jq -r ".[0].user.following = true" logs/user_tl.twbs > logs/user_tl.twbs.tmp  &&  mv logs/user_tl.twbs.tmp logs/user_tl.twbs 
    elif [ $# -eq 2 ]; then
        if [ "$1" = "logs/user_search.twbs" ]; then
            jq -r ".[$2].following = true" $1 > $1.tmp  &&  mv $1.tmp $1
        elif [ "$1" = "logs/tweet_search.twbs" ]; then
            jq -r ".statuses[$2].user.following = true" $1 > $1.tmp  &&  mv $1.tmp $1
        else
            jq -r ".[$2].user.following = true" $1 > $1.tmp  &&  mv $1.tmp $1
        fi

    fi

}

# Función que sube todos los archivos multimedia pasados por parámetro a Twitter.
# Devuelve sus ids separadas por "," para adjuntar a la petición de twittear
upload_media(){
    if [ $# -eq 0 ]; then
        echo ""
    else
        local args=("$@")
        local output=""
        for i in $( seq 0 $(( $# - 1 )) )
        do
            # Si el archivo no existe da un error
            if [ ! -s ${args[$i]} ]; then
                echo false
                break
            fi
            local response=$( echo "" | make_request POST https://upload.twitter.com/1.1/media/upload.json "${args[$i]}" )
            if echo $response | jq -e ". | objects | has(\"errors\")"  > /dev/null ; then
                error "No se ha podido subir el archivo ${args[$i]}"
                exit 1
            fi
            # Añade la nueva id al string de salida, separada por una ","
            output="$output,$( echo $response | jq -r ".media_id_string" )"
        done
        
        echo ${output:1}

    fi

}

# Función que busca usuarios en Twitter en base a palabras clave
# Uso: echo keywords | search_users
search_users(){
    local query=$( cat )
    local parameters="q $query"

    local response="$( echo "$parameters" | make_request GET https://api.twitter.com/1.1/users/search.json )"

    if echo $response | jq -e ". | objects | has(\"errors\")"  > /dev/null ; then
        error "No se ha podido realizar la búsqueda de usuario con las siguientes palabras clave: $query"
        exit 1
    fi

    echo "$response" > logs/user_search.twbs
    echo "$response" | print_users_search $query
}

# Función que busca tweets en Twitter en base a palabras clave
# Uso: echo keywords | search_tweets
search_tweets(){
    local query=$( cat )
    local parameters="q $query
    count $SEARCH_TWEETS
    tweet_mode extended"

    local response="$( echo "$parameters" | make_request GET https://api.twitter.com/1.1/search/tweets.json )"

    if echo $response | jq -e ". | objects | has(\"errors\")"  > /dev/null ; then
        error "No se ha podido realizar la búsqueda de tweets con las siguientes palabras clave: $query"
        exit 1
    fi

    echo "$response" > logs/tweet_search.twbs
    echo "$response" | print_tweets_search $query
    
}


#Funciones que actualizan los valores por defecto de las variables de entorno en el archivo de configuración
set_last_file(){
    local new_value=$1

    sed -i -e "s;LAST_FILE=\"$LAST_FILE\";LAST_FILE=\"$new_value\";" conf.twbs
}

set_tl_tweets(){
    local new_value=$1

    sed -i -e "s;TL_TWEETS=$TL_TWEETS;TL_TWEETS=$new_value;" conf.twbs
}

set_search_tweets(){
    local new_value=$1

    sed -i -e "s;SEARCH_TWEETS=$SEARCH_TWEETS;SEARCH_TWEETS=$new_value;" conf.twbs
}

set_user_tweets(){
    local new_value=$1

    sed -i -e "s;USER_TWEETS=$USER_TWEETS;USER_TWEETS=$new_value;" conf.twbs
}

set_my_screen_user_name(){
    local new_value=$1

    sed -i -e "s;MY_SCREEN_NAME=\"$MY_SCREEN_NAME\";MY_SCREEN_NAME=\"$new_value\";" conf.twbs
}

# Función que imprime el manual de ayuda para el script
twitter_help(){
    echo -e "\nUSO:"
    echo -e "./twitter [opción] argumentos.\n"

    echo -e "CONSIDERACIONES:"
    echo -e "Este script tiene un registro en el que almacena la ultima acción realizada por el usuario."\
    "Esto es así con la finalidad de hacer que la interacción sea más sencilla,"\
    "y para poder ejecutar acciones que se basen en el contenido impreso en la instrucción anterior.\n"

    echo -e "VARIABLES DE ENTORNO:"
    echo -e "TL_TWEETS:\t\t Número de tweets que se cargan en el timeline."
    echo -e "SEARCH_TWEETS:\t\t Número de tweets que se cargan en las búsquedas de tweets."
    echo -e "USER_TWEETS:\t\t Número de tweets que se cargan en los perfiles de usuario (tanto tweets como favoritos).\n"
    

    echo -e "OPCIONES:"
    echo -e "[nada|-tl|--timeline]\nImprime el timeline que hay almacenado en un log desde la última vez que se refrescó.\n"
    echo -e "[-r|--refresh]\nRefresca el timeline y lo almacena en un log. Después, lo muestra por pantalla. Cargará "\
    "tantos tweets como especifique la variable de entorno TL_TWEETS.\n"
    echo -e "[-m|--more]\nCarga tweets más antiguos en el timeline.\n"
    echo -e "[-rt|--retweet] index\nRetwittea el tweet con el índice pasado por parámetro. "\
    "El índice será el representado en la última impresión por pantalla. Si ya estaba retwitteado, lo desretwitteará.\n"
    echo -e "[-fav|--favorite] index\nAñade a favoritos el tweet con el índice pasado por parámetro. "\
    "El índice será el representado en la última impresión por pantalla. Si ya estaba en favoritos, lo eliminará.\n"
    echo -e "[-su|--search-users] keywords\nBusca usuarios con las palabras clave que se pasen como argumento.\n"
    echo -e "[-st|--search-tweets] keywords\nBusca tweets con las palabras clave que se pasen como argumento. Cargará "\
    "tantos tweets como especifique la variable de entorno SEARCH_TWEETS.\n"
    echo -e "[-u|--user|-ut|--user-tweets] index|username\nImprimira el perfil y los tweets y respuestas del usuario con el "\
    "índice o nombre de usuario pasado por parámetro. El índice será el representado en la última impresión por pantalla. Cargará "\
    "tantos tweets como especifique la variable de entorno USER_TWEETS.\n"
    echo -e "[-uf|--user-favs] index|username\nImprimira el perfil y los tweets favoritos del usuario con el "\
    "índice o nombre de usuario pasado por parámetro. El índice será el representado en la última impresión por pantalla. Cargará "\
    "tantos tweets como especifique la variable de entorno USER_TWEETS.\n"
    echo -e "[-f|--follow]\nSi la ultima impresión fue el perfil de un usuario, se seguirá a este. Si ya se seguía, se dejará de seguir.\n"
    echo -e "[-f|--follow] index|username\nSeguirá al usuario con el índice o nombre de usuario pasado como parámetro."\
    "El índice será el representado en la última impresión por pantalla.\n"
    echo -e "[-t|--tweet] status [media]*\nTwitteará el estado pasado como primer argumento. Adicionalmente, se pueden "\
    "pasar las rutas absolutas de hasta cuatro archivos multimedia para adjuntar al tweet.\n"
    echo -e "[-re|--reply] index status [media]*\nResponderá al tweet cuyo indice es pasado como primer argumento con el estado pasado "\
    "como segundo argumento. Adicionalmente, se pueden pasar las rutas absolutas de hasta cuatro archivos multimedia para adjuntar al tweet.\n"
    echo -e "[-l|--last-impression]\nImprime de nuevo la última impresión que se haya hecho.\n"
    echo -e "[-h|--help]\nMuestra este menú de ayuda.\n"
    echo -e "[-mod|--modify] varname value\nActualiza el valor de la variable de entorno pasada como primer argumento con el valor "\
    "pasado como segundo argumento. La modificación se conserva en la configuración del script para las próximas ejecuciones.\n"


    exit 0
}

# CÓDIGO PRINCIPAL

check_commands

# Si no se pasan parámetros, muestra el timeline
if [ $# -eq 0 ]; then
    # Comprueba que ya haya un log del tl antes de imprimirlo
    if [ ! -s logs/tl.twbs ]; then
        error "Para mostrar los tweets, debe haber tweets en el timeline: ./twitter.sh -r/--refresh"
        exit 1
    fi
    print_timeline
    info "Para actualizar el timeline: ./twitter.sh -r/--refresh"
    set_last_file logs/tl.twbs
    exit 0
fi

case $1 in

    -tl|--timeline) # Hace lo mismo que si no se le pasan parámetros
        if [ ! -s logs/tl.twbs ]; then
            error "Para mostrar los tweets, debe haber tweets en el timeline: ./twitter.sh -r/--refresh"
            exit 1
        fi
        print_timeline
        info "Para actualizar el timeline: ./twitter.sh -r/--refresh"
        set_last_file logs/tl.twbs
        exit 0
    ;;

    -r|--refresh) # Llama a la función que refresca el tl
        refresh_timeline
        set_last_file logs/tl.twbs
        exit 0
    ;;
        
    -m|--more) # Llama a la función que refresca el tl pasándole como id máximo el id del tweet más antiguo del tl. Así, cargará tweets más antiguos
        if [ ! -s logs/tl.twbs ]; then
            error "Para cargar más tweets, debe haber tweets en el timeline: ./twitter.sh -r/--refresh"
            exit 1
        fi
        refresh_timeline "$( cat logs/tl.twbs | jq -r ".[-1].id_str" )"
        set_last_file logs/tl.twbs
        exit 0
    ;;

    -su|--search-users) # Llama a la función que busca usuarios
        if [ ! $# -gt 1 ]; then
            error "Debes introducir las palabras clave a buscar"
            exit 1
        fi
        shift
        
        echo "$@" | search_users
        set_last_file logs/user_search.twbs
        exit 0
    ;;

    -st|--search-tweets) # Llama a la función que busca tweets
        if [ ! $# -gt 1 ]; then
            error "Debes introducir las palabras clave a buscar"
            exit 1
        fi
        shift

        echo "$@" | search_tweets
        set_last_file logs/tweet_search.twbs
        exit 0
    ;;

    -u|--user|-ut|--user-tweets) # Llama a la función que busca el perfil de un usuario concreto, dependiendo de los parámetros y de la última impresión
        if [ ! $# -gt 1 ] ; then
            error "Debes especificar el usuario cuyo perfil quieras ver: @user ó user ó índice en la última impresión."
            exit 1
        elif [ $# -gt 2 ] ; then
            error "Demasiados argumentos."
            exit 1
        elif ! [[ "$2" =~ ^[0-9]+$ ]]; then # Si no se le pasa un número, es que se le ha pasado el username
            get_user_profile -t $2
        else # Si se le pasa un número, es un índice, por lo que busca al usuario con ese índice en la última impresión
            if [ ! -s $LAST_FILE ]; then
                error "Para usar el índice debe haber habido una impresión antes."
                exit 1
            fi
            get_user_profile -t $LAST_FILE $2
        fi

        set_last_file logs/user_tl.twbs
        exit 0
    ;;

    -uf|--user-favs) # Llama a la función que busca el perfil de un usuario concreto (favs), dependiendo de los parámetros y de la última impresión
        if [ ! $# -gt 1 ] ; then
            error "Debes especificar el usuario cuyo perfil quieras ver: @user ó user ó índice en la última impresión."
            exit 1
        elif [ $# -gt 2 ] ; then
            error "Demasiados argumentos."
            exit 1
        elif ! [[ "$2" =~ ^[0-9]+$ ]]; then # Si no se le pasa un número, es que se le ha pasado el username
            get_user_profile -f $2
        else # Si se le pasa un número, es un índice, por lo que busca al usuario con ese índice en la última impresión
            if [ ! -s $LAST_FILE ]; then
                error "Para usar el índice debe haber habido una impresión antes."
                exit 1
            fi
            get_user_profile -f $LAST_FILE $2
        fi

        set_last_file logs/user_favs.twbs
        exit 0
    ;;


    -f|--follow) # Sigue a un usuario.
        if [ $# -gt 2 ]; then
            error "Demasiados argumentos."
            exit 1
        elif [ $# -eq 1 ]; then # Si no hay argumentos pero la última impresión es un perfil, entonces sigue a ese usuario
            if [ ! "$LAST_FILE" = "logs/user_tl.twbs" ] && [ ! "$LAST_FILE" = "logs/user_favs.twbs" ]; then
                error "Para seguir a un usuario introduce su @ o su indice en la ultima impresion. Si la ultima impresion fue su pagina de usuario, no necesitas pasar argumentos."
                exit 1
            fi
            if [ ! -s $LAST_FILE ]; then
                error "Ha habido un problema y debes especificar el nombre de usuario."
                exit 1
            fi
            call_follow_user 
        elif ! [[ "$2" =~ ^[0-9]+$ ]]; then # Si se le pasa algo que no es un número, es el username
            call_follow_user $2
        else
            if [ ! -s $LAST_FILE ]; then # Si es un número, es el índice de la última impresión
                error "Para usar el índice debe haber habido una impresión antes."
                exit 1
            fi
            call_follow_user $LAST_FILE $2
        fi
        exit 0
    ;; 

    -rt|--retweet) # Llama a dar retweet con el índice que le pasan
        if [ $# -gt 2 ]; then
            error "Demasiados argumentos."
            exit 1
        elif [ $# -eq 1 ]; then
            error "Debes especificar el índice del tweet."
            exit 1
        else
            if [ "$LAST_FILE" = "logs/user_search.twbs" ]; then # Si la última impresión fue una búsqueda de usuarios, no hay nada que retwittear
                error "No puedes retwittear nada en una busqueda de usuarios."
                exit 1
            fi
            if [ ! -s $LAST_FILE ]; then 
                error "Para usar el índice debe haber habido una impresión antes."
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then 
                error "El segundo argumento debe ser un número"
                exit 1
            fi
            retweet_by_index $LAST_FILE $2
        fi

        exit 0
    ;;

    -fav|--favorite) # Llama a dar favs con el índice que le pasan
        if [ $# -gt 2 ]; then
            error "Demasiados argumentos."
            exit 1
        elif [ $# -eq 1 ]; then
            error "Debes especificar el índice del tweet."
            exit 1
        else
            if [ "$LAST_FILE" = "logs/user_search.twbs" ]; then # Si la última impresión fue una búsqueda de usuarios, no hay nada a lo que dar favs
                error "No puedes dar favoritos a nada en una busqueda de usuarios."
                exit 1
            fi
            if [ ! -s $LAST_FILE ]; then 
                error "Para usar el índice debe haber habido una impresión antes."
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then 
                error "El segundo argumento debe ser un número"
                exit 1
            fi
            favorite_by_index $LAST_FILE $2
        fi

        exit 0
    ;;

    -t|--tweet) # Llama a la función de twittear
        if [ $# -eq 1 ]; then
            error "Debes especificar lo que quieres twittear."
            exit 1
        elif [ $# -eq 2 ]; then
            echo "$2" | update_status
            exit 0 
        elif [ $# -gt 6 ]; then
            error "Demasiados argumentos. No puedes subir más de 4 fotos."
            exit 1
        else # Si se le pasa mas de un argumento, entonces es que son archivos multimedia. Por lo tanto, llama a la funcion upload_media y pasa el resultado a update_status
            media=$( upload_media $3 $4 $5 $6)
            if [ ! $media = false ]; then
                echo "$2" | update_status "$media"
            else
                error "No existe el fichero."
            fi
        fi

        exit 0
    ;;

    -re|--reply) # Llama a la función update_status pero esta vez con el id del tweet a responder y, eventualmente, con archivos mmedia
        if [ $# -le 2 ]; then
            error "Debes especificar lo que quieres twittear y el índice del tweet a responder."
            exit 1
        elif [ $# -eq 3 ]; then
            echo "$3" | update_status "" $LAST_FILE $2
            exit 0 
        elif [ $# -gt 7 ]; then
            error "Demasiados argumentos. No puedes subir más de 4 fotos."
            exit 1
        else
            if [ ! -s $LAST_FILE ]; then 
                error "Para usar el índice debe haber habido una impresión antes."
                exit 1
            fi
            media=$( upload_media $4 $5 $6 $7)
            if [ ! $media = false ]; then
                echo "$3" | update_status "$media" $LAST_FILE $2
            else
                error "No existe el fichero."
            fi
        fi

        exit 0

    ;;

    # Imprime de nuevo la última impresión 
    -l|--last-impression)
        if [ ! -s $OUTPUT_FILE ]; then
            error "No hay almacenado un log con la última impresión."
            exit 1
        fi
        cat $OUTPUT_FILE | less -r
        # Avisa al usuario de que los datos no están actualizados
        warning "Al usar la funcion -l/--last-impression, los datos no se encuentran actualizados. Por ejemplo, no se verá reflejado si has dado retweet a algún tweet."
        exit 0
    ;;

    -h|--help) # Llama a mostrar el menú de ayuda
        twitter_help
        exit 0
    ;;

    -mod|--modify) # Modifica las variables de entorno en el archivo de configuración siempre que los nuevos valores sean válidos
        if [ "$2" = "TL_TWEETS" ]; then
            if [ $3 -gt 0 ] && [ $3 -le 200 ]; then
                set_tl_tweets $3
            else
                error "El valor de TL_TWEETS debe estar entre 1 y 200."
                exit 1
            fi
        elif [ "$2" = "SEARCH_TWEETS" ]; then
            if [ $3 -gt 0 ] && [ $3 -le 200 ]; then
                set_search_tweets $3
            else
                error "El valor de SEARCH_TWEETS debe estar entre 1 y 100."
                exit 1
            fi
        elif [ "$2" = "USER_TWEETS" ]; then
            if [ $3 -gt 0 ] && [ $3 -le 200 ]; then
                set_user_tweets $3
            else
                error "El valor de USER_TWEETS debe estar entre 1 y 200."
                exit 1
            fi
        elif [ "$2" = "MY_SCREEN_NAME" ]; then
            set_my_screen_user_name $3
        else
            error "No existe esa variable o no se puede cambiar."
            exit 1
        fi
        info "Se ha cambiado con éxito la variable $2 a $3"
        exit 0

    ;;

    *) # Imprime un error
        error "Opción no válida $1. Prueba --help para más información."
        exit 1

esac


