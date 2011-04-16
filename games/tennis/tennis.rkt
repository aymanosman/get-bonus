#lang racket/gui
(require racket/runtime-path
         "../../exp/loop.rkt"
         (prefix-in gl: "../../exp/gl.rkt")
         "../../exp/sprites.rkt"
         "../../exp/mvector.rkt"
         "../../exp/fullscreen.rkt"
         "../../exp/keyboard.rkt"
         "../../exp/mapping.rkt"
         "../../exp/controller.rkt"
         "../../exp/joystick.rkt"
         "../../exp/3s.rkt"
         "../../exp/psn.rkt"
         (prefix-in cd: "../../exp/cd-narrow.rkt"))

(define-runtime-path resource-path "r")

(define-syntax-rule (define-sound id f)
  (define id (path->audio (build-path resource-path f))))

(define-sound se:applause "applause.wav")
(define-sound se:bgm "bgm.mp3")
(define-sound se:bump-lhs "bump-lhs.mp3")
(define-sound se:bump-rhs "bump-rhs.mp3")
(define-sound se:bump-wall "bump-wall.wav")

(define width 16.)
(define height 9.)
(define center-pos
  (psn (/ width 2.) (/ height 2.)))
(define speed 
  (* 4. RATE))
(define ball-speed
  (* 1.5 speed))

(define paddle-w
  .5)
(define paddle-hw
  (/ paddle-w 2))
(define paddle-h
  (/ height 9))
(define paddle-hh
  (/ paddle-h 2))

(define min-paddle-y
  paddle-hh)
(define max-paddle-y
  (- height paddle-hh))

(define paddle
  (gl:rectangle paddle-w paddle-h))

(define ball-r .25)
(define ball
  (gl:color 0 255 0 0
            (gl:scale ball-r ball-r (gl:circle))))

(define lhs-x 
  (- .5 paddle-hw))
(define rhs-x 
  (- width .5 paddle-hw))

(struct world (frame lhs-score rhs-score
                     lhs-y
                     ball-pos ball-dir ball-target
                     rhs-y))

(define frame-top
  (cd:aabb (+ center-pos (psn 0. height)) (/ width 2.) (/ height 2.)))
(define frame-bot
  (cd:aabb (- center-pos (psn 0. height)) (/ width 2.) (/ height 2.)))

(define (clamp bot x top)
  (max bot (min x top)))

(define (between lo hi)
  (+ lo (* (random) (- hi lo))))
(define (random-dir t)
  (case t
    [(left) 
     (between (* 2/3 pi) (* 4/3 pi))]
    [(right)
     (between (* 5/3 pi) (* 7/3 pi))]))
(define (start-pos dir)
  (case dir
    [(right) (- center-pos (/ width 4))]
    [(left) (+ center-pos (/ width 4))]))

; XXX Start screen
; XXX Pause in between serves?
(big-bang
 (let ()
   (define first-target
     (case (random 2)
       [(0) 'left]
       [(1) 'right]))
   (world 0
          0 0
          4.5
          (start-pos first-target) (random-dir first-target) first-target
          4.5))
 #:tick
 (λ (w cs)
   (match-define (world 
                  frame lhs-score rhs-score
                  lhs-y
                  ball-pos ball-dir ball-tar
                  rhs-y)
                 w)
   (match-define 
    (list (app controller-dpad
               (app psn-y
                    lhs-dy))
          (app controller-dpad
               (app psn-y
                    rhs-dy)))
    (if (= (length cs) 2)
        cs
        (list (first cs)
              (controller (psn 0. 
                               ; Goes towards the ball's y position
                               (clamp -1. (/ (- (psn-y ball-pos) rhs-y) speed) 1.))
                          0. 0.
                          #f #f #f #f 
                          #f #f #f #f #f #f))))
   
   (define lhs-y-n
     (clamp
      min-paddle-y
      (+ lhs-y (* lhs-dy speed))
      max-paddle-y))
   (define rhs-y-n
     (clamp
      min-paddle-y
     (+ rhs-y (* rhs-dy speed))
      max-paddle-y))
   (define (ball-in-dir dir)
     (+ ball-pos (make-polar ball-speed dir)))
   (define ball-pos-m
     (ball-in-dir ball-dir))
   
   (define ball-shape
     (cd:circle ball-pos-m ball-r))
   (define lhs-shape
     (cd:aabb (psn (+ lhs-x paddle-hw) lhs-y-n) paddle-hw paddle-hh))
   (define rhs-shape
     (cd:aabb (psn (+ rhs-x paddle-hw) rhs-y-n) paddle-hw paddle-hh))
   
   ; XXX I can tell if it is the top/bot of the ball by the centers
   ; XXX The lhs/rhs sounds are too low. This is the openal "scale" problem, so i have faked their distance
   (define-values
     (ball-pos-n+ ball-dir-n ball-tar-n sounds)
     (cond
       [; The ball hit the top
        (cd:shape-vs-shape ball-shape frame-top)
        (values ball-pos
                (case ball-tar
                  [(left) (between 3.2 4.2)]
                  [(right) (between 5.2 6.2)])
                ball-tar
                (list (sound-at se:bump-wall ball-pos-m)))]
       [; The ball hit the bot
        (cd:shape-vs-shape ball-shape frame-bot)
        (values ball-pos
                (case ball-tar
                  [(left) (between 2.1 3.0)]
                  [(right) (between 0.2 1.1)])
                ball-tar
                (list (sound-at se:bump-wall ball-pos-m)))]
       [; The ball has bounced off the lhs
        (cd:shape-vs-shape ball-shape lhs-shape)
        (values ball-pos
                (random-dir 'right) 'right
                (list (sound-at se:bump-lhs (- center-pos 1.))))]
       [; The ball has bounced off the rhs
        (cd:shape-vs-shape ball-shape rhs-shape)
        (values ball-pos
                (random-dir 'left) 'left
                (list (sound-at se:bump-rhs (+ center-pos 1.))))]
       ; The ball is inside the frame
       [else
        (values ball-pos-m ball-dir ball-tar empty)]))
   (define ball-pos-n
     (if (= ball-dir-n ball-dir)
         ball-pos-n+
         (ball-in-dir ball-dir-n)))
   
   ; XXX Maybe I should implement serving?
   (define-values
     (ball-pos-p ball-dir-p ball-tar-p lhs-score-n rhs-score-n score?)
     (cond
       ; The ball has moved to the left of the lhs paddle
       [((psn-x ball-pos-n) . < . lhs-x)
        (values (start-pos 'right) (random-dir 'right) 'right
                lhs-score (add1 rhs-score) #t)]
       ; The ball has moved to the right of the rhs paddle
       [((psn-x ball-pos-n) . > . rhs-x)
        (values (start-pos 'left) (random-dir 'left) 'left
                (add1 lhs-score) rhs-score #t)]
       [else
        (values ball-pos-n ball-dir-n ball-tar-n lhs-score rhs-score #f)]))
   
   (values 
    (world 
     (add1 frame)
     lhs-score-n rhs-score-n
     lhs-y-n
     ball-pos-p ball-dir-p ball-tar-p
     rhs-y-n)
    (gl:focus 
     width height width height
     (psn-x center-pos) (psn-y center-pos)
     (gl:background
      255 255 255 0
      #;(gl:translate 0. 0.
                      (gl:texture
                       (gl:string->texture #:size 30 (real->decimal-string (current-rate)))))
      ; XXX Place the scores better
      (gl:translate (* width 1/4) (* height 8/9)
                              (gl:texture
                               (gl:string->texture #:size 30 (format "~a" lhs-score-n))))
                (gl:translate (* width 3/4) (* height 8/9)
                              (gl:texture
                               (gl:string->texture #:size 30 (format "~a" rhs-score-n))))
      ; XXX Change the paddle graphics
      (gl:translate lhs-x (- lhs-y-n paddle-hh)
                    (gl:color 255 0 0 0
                              paddle))
      (gl:translate rhs-x (- rhs-y-n paddle-hh)
                    (gl:color 0 0 255 0
                              paddle))
      ; XXX Change the ball graphic
      ; XXX Animate the ball
      (gl:translate (psn-x ball-pos-p) (psn-y ball-pos-p)
                    ball)))
    ; XXX Make the ball whoosh
    ; XXX Make scores have calls
    (append
     sounds
     (if score?
         (list (sound-at se:applause center-pos))
         empty)
     (if (zero? frame)
         (list (background (λ (w) se:bgm) #:gain 0.1))
         empty))))
 #:listener
 (λ (w) center-pos)
 #:done?
 ; XXX Look at score
 (λ (w) #f))
