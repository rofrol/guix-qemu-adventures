for url in https://bordeaux.guix.gnu.org https://ci.guix.gnu.org https://cache-cdn.guix.moe https://mirror.yandex.ru/mirrors/guix; do
	echo -n "$url: "
	curl -s -o /dev/null -w "%{time_connect} seconds\n" "$url"
done
