source colors.txt

OUTPUT_FILE=logs/tmp_output.twbs

# Función para testear cosas e imprimir. Funciona si la variable de entorno DEBUG existe
log() {
  [ "$DEBUG" = '' ] && return 0
  echo "$*" 
}

# Función que imprime errores en rojo
error(){
  echo -e "${schar}${red}Error: ${@}${schar}${white}"
}

# Función que imprime mensajes informativos en verde
info(){
  echo -e "${schar}${green}${@}${schar}${white}"
}

# Función que imprime advertencias en naranja
warning(){
  echo -e "ADVERTENCIA: ${schar}${orange}${@}${schar}${white}"
}

# Imprime los tweets de un archivo
print_tweets(){
  local tweets_json=$( cat )
  
  # Comprueba que haya tweets en la entrada
  if [ $( echo $tweets_json | jq ". | length" ) -eq 0 ];then
    info "No hay tweets para imprimir"
    exit 0
  fi

  # Imprime los tweets uno a uno
  for i in $( seq 0 $( echo $tweets_json | jq ". | length - 1" ) ) ; do
    echo -ne "${schar}${blue}[$i] ${schar}${white}" >> $OUTPUT_FILE

    if echo $tweets_json | jq -e ".[$i] | has(\"retweeted_status\")" > /dev/null ; then
      local tweet="[$i].retweeted_status"
      echo $tweets_json | jq -r ".[$i].user.name" | print_retweet_user 
    else
      local tweet="[$i]"
    fi
    # Va guardando los tweets campo a campo en el archivo de salida, pasando cada campo por una función diferente que los imprime con un determinado formato.
    echo $tweets_json | jq -r ".$tweet.user.name" | print_user_name 
    echo $tweets_json | jq -r ".$tweet.user.screen_name" | print_user_screen_name 
    echo $tweets_json | jq -r ".$tweet.full_text" | print_tweet_body 
    echo $tweets_json | jq -r ".$tweet.created_at" | print_date
    if echo $tweets_json | jq -e ".$tweet.retweeted" > /dev/null ; then
      echo $tweets_json | jq -r ".$tweet.retweet_count" | print_tweet_retweets_mark 
    else
      echo $tweets_json | jq -r ".$tweet.retweet_count" | print_tweet_retweets 
    fi

    if echo $tweets_json | jq -e ".$tweet.favorited" > /dev/null; then
      echo $tweets_json | jq -r ".$tweet.favorite_count" | print_tweet_likes_mark
    else
      echo $tweets_json | jq -r ".$tweet.favorite_count" | print_tweet_likes
    fi
    
  done

  # Imprime todos los tweets a la vez con less para que sea más interactivo
  cat $OUTPUT_FILE | less -r
}

# Funciones para imprimir cada campo

print_retweet_user(){
  echo -e "Retwitteado por $( cat )" >> $OUTPUT_FILE
}

print_user_name(){
  echo -en "$( cat )   " >> $OUTPUT_FILE
}

print_user_screen_name(){
  echo -e "${schar}${gray}@$( cat )\n${schar}${white}" >> $OUTPUT_FILE
}

print_date(){
  echo -e "\t${schar}${gray}$( cat )${schar}${white}\n" >> $OUTPUT_FILE
}

print_tweet_body(){
  echo -e "$( cat )\n" | fold | awk '{ print "\t" $0 }' >> $OUTPUT_FILE
}

print_tweet_retweets(){
  echo -en "$( cat ) retweets \t \t" >> $OUTPUT_FILE
}

print_tweet_likes(){
  echo -e "$( cat ) likes\n\n" >> $OUTPUT_FILE
}

print_tweet_retweets_mark(){
  echo -en "${schar}${green}$( cat ) retweets \t \t${schar}${white}" >> $OUTPUT_FILE
}

print_tweet_likes_mark(){
  echo -e "${schar}${pink}$( cat ) likes\n\n${schar}${white}" >> $OUTPUT_FILE
}

print_title(){
  echo -e "$( cat )\n\n" >> $OUTPUT_FILE
}

print_location(){
  echo -e "${schar}${orange}Ubicación: $( cat )${schar}${white}" >> $OUTPUT_FILE
}

print_description(){
  echo -e "$( cat )\n" | fold | awk '{ print "\t" $0 }' >> $OUTPUT_FILE
}

print_url(){
  echo -e "${schar}${light_blue}$( cat )\n${schar}${white}" >> $OUTPUT_FILE
}

print_followers(){
  echo -en "$( cat ) seguidores \t\t" >> $OUTPUT_FILE
}

print_following(){
  echo -e "$( cat ) siguiendo\n\n" >> $OUTPUT_FILE
}

# Imprime los tweets de una tl (home o usuario), poniendo un título encima.
print_timeline(){
    echo "" > $OUTPUT_FILE
    echo "HOME" | print_title
    if [ ! $# -eq 0 ]; then
        echo $1 | print_tweets
    else
        cat logs/tl.twbs | print_tweets
    fi
}

# Imprime el usuario resultado de una búsqueda junto a sus tweets o sus favoritos
print_user_profile(){
  echo "" > $OUTPUT_FILE
  local info=$( cat logs/user_tl.twbs | jq ".[0]") 
  echo $info | jq -r ".user.name" | print_user_name
  echo $info | jq -r ".user.screen_name" | print_user_screen_name
  echo $info | jq -r ".user.description" | print_description 

  # La ubicación y la url solo se imprimen si el usuario tiene
  local location=$( echo $info | jq -r ".user.location")
  if [ ! "$location" = "" ]; then
    echo $location | print_location 
  fi

  local url=$( echo $info | jq -r ".user.url" )
  if [ ! "$url" = "null" ]; then
    echo $url | print_url 
  fi

  # Imprime información sobre si ya se sigue o no al usuario
  if [ "$( echo $info | jq -e ".user.following" )" = "true" ] ; then
    echo -e "${schar}${gray}YA SIGUES A ESTE USUARIO${schar}${white}" >> $OUTPUT_FILE
  else
    echo -e "${schar}${gray}NO SIGUES A ESTE USUARIO${schar}${white}" >> $OUTPUT_FILE
  fi

  echo $info | jq -r ".user.followers_count" | print_followers  
  echo $info | jq -r ".user.friends_count" | print_following 

  # Imprime los tweets o favs del usuario dependiendo de la opción que se pase por parámetro
  if [ "$1" = '-t' ]; then
    echo "TWEETS Y RESPUESTAS" | print_title 
    cat logs/user_tl.twbs | print_tweets
  else
    echo "FAVORITOS" | print_title 
    cat logs/user_favs.twbs | print_tweets
  fi
}

# Imprime información muy básica de un usuario para las búsquedas
print_user_search(){
  local info=$( cat ) 
  echo $info | jq -r ".name" | print_user_name
  echo $info | jq -r ".screen_name" | print_user_screen_name
  echo $info | jq -r ".description" | print_description 


  if [ "$( echo $info | jq -e ".user.following" )" = "true" ] ; then
    echo -e "${schar}${gray}YA SIGUES A ESTE USUARIO${schar}${white}" >> $OUTPUT_FILE
  else
    echo -e "${schar}${gray}NO SIGUES A ESTE USUARIO${schar}${white}" >> $OUTPUT_FILE
  fi
  
  echo $info | jq -r ".followers_count" | print_followers  
  echo $info | jq -r ".friends_count" | print_following 
}

# Imprime a los usuarios uno a uno del resultado de una búsqueda
print_users_search(){
  echo "" > $OUTPUT_FILE
  users_json=$( cat )

  if [ $( echo $users_json | jq ". | length" ) -eq 0 ];then
    info "No hay usuarios para imprimir"
    exit 0
  fi

  echo "RESULTADO DE LA BÚSQUEDA (USUARIOS): $1" | print_title

  for i in $( seq 0 $( echo $users_json | jq ". | length - 1" ) ) ; do
    echo -ne "${schar}${blue}[$i] ${schar}${white}" >> $OUTPUT_FILE

    echo $users_json | jq ".[$i]" | print_user_search
    
  done

  cat $OUTPUT_FILE | less -r
}

# Imprime los tweets resultantes de una búsqueda
print_tweets_search(){
  echo "" > $OUTPUT_FILE
  echo "RESULTADO DE LA BÚSQUEDA (TWEETS): $1" | print_title

  echo $( cat ) | jq ".statuses" | print_tweets
}