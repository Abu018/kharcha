package middleware

import (
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

type statusRecoder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecoder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

type Log struct {
	Time   time.Time
	Ip     string
	Method string
	Path   string
	Status int
}

var (
	buffer    = make(chan Log, 1000)
	startOnce sync.Once
)

func Logging(next http.Handler, w http.ResponseWriter, r *http.Request) {
	ipClient := ClientIp(r)
	rec := &statusRecoder{ResponseWriter: w, status: http.StatusOK}
	e := Log{
		Time:   time.Now(),
		Ip:     ipClient,
		Method: r.Method,
		Path:   r.URL.Path,
		Status: rec.status,
	}

	next.ServeHTTP(w, r)
	select {
	case buffer <- e:
	default:
	}
}
func ClientIp(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		parts := strings.Split(xff, ",")
		ip := strings.TrimSpace(parts[0])
		if net.ParseIP(ip) != nil {
			return ip
		}
	}
	if xri := r.Header.Get("X-Real-Ip"); xri != "" {
		if net.ParseIP(xri) != nil {
			return xri
		}
	}
	ip, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil {
		return ip
	}
	return r.RemoteAddr
}

func Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {

		Logging(next, w, r)

	})
}
