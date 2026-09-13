// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchActivityStrings {
    let timer: String
    let timerDescription: String
    let pomodoro: String
    let focus: String
    let shortBreak: String
    let longBreak: String
    let pomodoroHint: String
    let minutes: String
    let start: String
    let resume: String
    let finished: String
    let camera: String
    let cameraUnavailable: String
    let cameraHint: String
    let startCamera: String
    let stopCamera: String
    let accessories: String
    let accessoryDescription: String
    let connected: String
    let lowBattery: String

    func phase(_ phase: NotchTimerPhase) -> String {
        switch phase {
        case .timer: return timer
        case .focus: return focus
        case .shortBreak: return shortBreak
        case .longBreak: return longBreak
        }
    }
}

extension FeatureStrings {
    static func notchActivities(_ language: AppLanguage) -> NotchActivityStrings {
        switch language {
        case .enUS: return NotchActivityStrings(
            timer: "Timer",
            timerDescription: "Timers and focused work sessions in the notch.",
            pomodoro: "Pomodoro",
            focus: "Focus",
            shortBreak: "Short break",
            longBreak: "Long break",
            pomodoroHint: "25 min of focus, 5 min of rest. A 15 min break after four focus sessions. Start each phase when you are ready.",
            minutes: "Minutes",
            start: "Start",
            resume: "Resume",
            finished: "Time is up",
            camera: "Camera mirror",
            cameraUnavailable: "The camera could not start. Try opening it again.",
            cameraHint: "Open a live mirror here. The camera stops when you leave this view.",
            startCamera: "Open camera",
            stopCamera: "Stop camera",
            accessories: "Accessory alerts",
            accessoryDescription: "Show connected accessories and warn once when their battery falls to 20%.",
            connected: "Connected",
            lowBattery: "Low battery")
        case .ptBR: return NotchActivityStrings(
            timer: "Temporizador",
            timerDescription: "Temporizadores e sessões de foco no notch.",
            pomodoro: "Pomodoro",
            focus: "Foco",
            shortBreak: "Pausa curta",
            longBreak: "Pausa longa",
            pomodoroHint: "25 min de foco, 5 min de pausa. Pausa de 15 min após quatro sessões de foco. Comece cada etapa quando estiver pronto.",
            minutes: "Minutos",
            start: "Iniciar",
            resume: "Continuar",
            finished: "Tempo esgotado",
            camera: "Espelho da câmera",
            cameraUnavailable: "Não foi possível iniciar a câmera. Tente abri-la novamente.",
            cameraHint: "Abra um espelho ao vivo aqui. A câmera para ao sair desta tela.",
            startCamera: "Abrir câmera",
            stopCamera: "Parar câmera",
            accessories: "Avisos de acessórios",
            accessoryDescription: "Mostra acessórios conectados e avisa uma vez quando a bateria cai para 20%.",
            connected: "Conectado",
            lowBattery: "Bateria baixa")
        case .es: return NotchActivityStrings(
            timer: "Temporizador",
            timerDescription: "Temporizadores y sesiones de concentración en el notch.",
            pomodoro: "Pomodoro",
            focus: "Concentración",
            shortBreak: "Descanso corto",
            longBreak: "Descanso largo",
            pomodoroHint: "25 min de concentración, 5 min de descanso. Descanso de 15 min tras cuatro sesiones. Inicia cada fase cuando quieras.",
            minutes: "Minutos",
            start: "Iniciar",
            resume: "Continuar",
            finished: "Se acabó el tiempo",
            camera: "Espejo de cámara",
            cameraUnavailable: "No se pudo iniciar la cámara. Intenta abrirla de nuevo.",
            cameraHint: "Abre un espejo en directo aquí. La cámara se detiene al salir de esta vista.",
            startCamera: "Abrir cámara",
            stopCamera: "Detener cámara",
            accessories: "Avisos de accesorios",
            accessoryDescription: "Muestra accesorios conectados y avisa una vez cuando la batería baja al 20 %.",
            connected: "Conectado",
            lowBattery: "Batería baja")
        case .de: return NotchActivityStrings(
            timer: "Timer",
            timerDescription: "Timer und konzentrierte Arbeitsphasen im Notch.",
            pomodoro: "Pomodoro",
            focus: "Fokus",
            shortBreak: "Kurze Pause",
            longBreak: "Lange Pause",
            pomodoroHint: "25 Min. Fokus, 5 Min. Pause. Nach vier Fokusphasen folgt eine Pause von 15 Min. Starte jede Phase, wenn du bereit bist.",
            minutes: "Minuten",
            start: "Starten",
            resume: "Fortsetzen",
            finished: "Zeit abgelaufen",
            camera: "Kameraspiegel",
            cameraUnavailable: "Die Kamera konnte nicht starten. Versuche, sie erneut zu öffnen.",
            cameraHint: "Öffne hier ein Live-Spiegelbild. Die Kamera stoppt beim Verlassen dieser Ansicht.",
            startCamera: "Kamera öffnen",
            stopCamera: "Kamera stoppen",
            accessories: "Zubehörhinweise",
            accessoryDescription: "Zeigt verbundenes Zubehör und warnt einmal, wenn der Batteriestand auf 20 % fällt.",
            connected: "Verbunden",
            lowBattery: "Batterie schwach")
        case .fr: return NotchActivityStrings(
            timer: "Minuteur",
            timerDescription: "Des minuteurs et des séances de concentration dans le notch.",
            pomodoro: "Pomodoro",
            focus: "Concentration",
            shortBreak: "Pause courte",
            longBreak: "Pause longue",
            pomodoroHint: "25 min de concentration, 5 min de pause. Une pause de 15 min après quatre séances. Commencez chaque étape à votre rythme.",
            minutes: "Minutes",
            start: "Démarrer",
            resume: "Reprendre",
            finished: "Temps écoulé",
            camera: "Miroir de la caméra",
            cameraUnavailable: "La caméra n’a pas pu démarrer. Essayez de l’ouvrir à nouveau.",
            cameraHint: "Ouvrez un miroir en direct ici. La caméra s’arrête lorsque vous quittez cette vue.",
            startCamera: "Ouvrir la caméra",
            stopCamera: "Arrêter la caméra",
            accessories: "Alertes des accessoires",
            accessoryDescription: "Affiche les accessoires connectés et avertit une fois quand leur batterie atteint 20 %.",
            connected: "Connecté",
            lowBattery: "Batterie faible")
        case .it: return NotchActivityStrings(
            timer: "Timer",
            timerDescription: "Timer e sessioni di concentrazione nel notch.",
            pomodoro: "Pomodoro",
            focus: "Concentrazione",
            shortBreak: "Pausa breve",
            longBreak: "Pausa lunga",
            pomodoroHint: "25 min di concentrazione, 5 min di pausa. Una pausa di 15 min dopo quattro sessioni. Inizia ogni fase quando vuoi.",
            minutes: "Minuti",
            start: "Avvia",
            resume: "Riprendi",
            finished: "Tempo scaduto",
            camera: "Specchio della fotocamera",
            cameraUnavailable: "Impossibile avviare la fotocamera. Prova ad aprirla di nuovo.",
            cameraHint: "Apri uno specchio dal vivo qui. La fotocamera si ferma quando esci da questa vista.",
            startCamera: "Apri fotocamera",
            stopCamera: "Ferma fotocamera",
            accessories: "Avvisi accessori",
            accessoryDescription: "Mostra gli accessori connessi e avvisa una volta quando la batteria scende al 20%.",
            connected: "Connesso",
            lowBattery: "Batteria scarica")
        case .ru: return NotchActivityStrings(
            timer: "Таймер",
            timerDescription: "Таймеры и сеансы сосредоточенной работы в вырезе экрана.",
            pomodoro: "Помодоро",
            focus: "Работа",
            shortBreak: "Короткий перерыв",
            longBreak: "Длинный перерыв",
            pomodoroHint: "25 мин работы, 5 мин отдыха. Перерыв на 15 мин после четырёх сеансов. Начинайте каждый этап, когда будете готовы.",
            minutes: "Минуты",
            start: "Начать",
            resume: "Продолжить",
            finished: "Время вышло",
            camera: "Зеркало камеры",
            cameraUnavailable: "Не удалось запустить камеру. Попробуйте открыть её снова.",
            cameraHint: "Откройте зеркало здесь. Камера остановится, когда вы покинете этот экран.",
            startCamera: "Открыть камеру",
            stopCamera: "Остановить камеру",
            accessories: "Оповещения об аксессуарах",
            accessoryDescription: "Показывает подключённые аксессуары и предупреждает один раз при снижении заряда до 20%.",
            connected: "Подключено",
            lowBattery: "Низкий заряд")
        case .tr: return NotchActivityStrings(
            timer: "Zamanlayıcı",
            timerDescription: "Çentikte zamanlayıcılar ve odaklanma oturumları.",
            pomodoro: "Pomodoro",
            focus: "Odaklanma",
            shortBreak: "Kısa mola",
            longBreak: "Uzun mola",
            pomodoroHint: "25 dk odaklanma, 5 dk mola. Dört oturumdan sonra 15 dk mola. Her aşamayı hazır olduğunuzda başlatın.",
            minutes: "Dakika",
            start: "Başlat",
            resume: "Sürdür",
            finished: "Süre doldu",
            camera: "Kamera aynası",
            cameraUnavailable: "Kamera başlatılamadı. Yeniden açmayı deneyin.",
            cameraHint: "Burada canlı bir ayna açın. Bu görünümden çıkınca kamera durur.",
            startCamera: "Kamerayı aç",
            stopCamera: "Kamerayı durdur",
            accessories: "Aksesuar uyarıları",
            accessoryDescription: "Bağlı aksesuarları gösterir ve pil %20’ye düştüğünde bir kez uyarır.",
            connected: "Bağlandı",
            lowBattery: "Pil zayıf")
        case .ja: return NotchActivityStrings(
            timer: "タイマー",
            timerDescription: "ノッチでタイマーと集中セッションを使えます。",
            pomodoro: "ポモドーロ",
            focus: "集中",
            shortBreak: "短い休憩",
            longBreak: "長い休憩",
            pomodoroHint: "25分集中し、5分休憩します。集中セッション4回ごとに15分休憩します。準備ができたら次の段階を開始してください。",
            minutes: "分",
            start: "開始",
            resume: "再開",
            finished: "時間になりました",
            camera: "カメラミラー",
            cameraUnavailable: "カメラを開始できませんでした。もう一度開いてください。",
            cameraHint: "ここでライブミラーを開きます。この画面を離れるとカメラは停止します。",
            startCamera: "カメラを開く",
            stopCamera: "カメラを停止",
            accessories: "アクセサリの通知",
            accessoryDescription: "接続したアクセサリを表示し、バッテリーが20%に低下したときに一度通知します。",
            connected: "接続済み",
            lowBattery: "バッテリー残量低下")
        case .ko: return NotchActivityStrings(
            timer: "타이머",
            timerDescription: "노치에서 타이머와 집중 세션을 사용하세요.",
            pomodoro: "뽀모도로",
            focus: "집중",
            shortBreak: "짧은 휴식",
            longBreak: "긴 휴식",
            pomodoroHint: "25분 집중, 5분 휴식. 네 번의 집중 세션 후 15분 휴식. 준비되면 각 단계를 시작하세요.",
            minutes: "분",
            start: "시작",
            resume: "계속",
            finished: "시간 종료",
            camera: "카메라 거울",
            cameraUnavailable: "카메라를 시작할 수 없습니다. 다시 열어 보세요.",
            cameraHint: "여기서 실시간 거울을 여세요. 이 화면을 나가면 카메라가 멈춥니다.",
            startCamera: "카메라 열기",
            stopCamera: "카메라 중지",
            accessories: "액세서리 알림",
            accessoryDescription: "연결된 액세서리를 표시하고 배터리가 20%로 떨어지면 한 번 알립니다.",
            connected: "연결됨",
            lowBattery: "배터리 부족")
        case .zhHans: return NotchActivityStrings(
            timer: "计时器",
            timerDescription: "在刘海中使用计时器和专注时段。",
            pomodoro: "番茄钟",
            focus: "专注",
            shortBreak: "短休息",
            longBreak: "长休息",
            pomodoroHint: "专注25分钟，休息5分钟。每四次专注后休息15分钟。准备好后再开始下一阶段。",
            minutes: "分钟",
            start: "开始",
            resume: "继续",
            finished: "时间到",
            camera: "摄像头镜像",
            cameraUnavailable: "无法启动摄像头，请尝试重新打开。",
            cameraHint: "在此打开实时镜像。离开此视图时摄像头会停止。",
            startCamera: "打开摄像头",
            stopCamera: "停止摄像头",
            accessories: "配件提醒",
            accessoryDescription: "显示已连接的配件，并在电量降至20%时提醒一次。",
            connected: "已连接",
            lowBattery: "电量低")
        case .zhTW: return NotchActivityStrings(
            timer: "計時器",
            timerDescription: "在瀏海中使用計時器與專注時段。",
            pomodoro: "番茄鐘",
            focus: "專注",
            shortBreak: "短休息",
            longBreak: "長休息",
            pomodoroHint: "專注25分鐘，休息5分鐘。每四次專注後休息15分鐘。準備好後再開始下一階段。",
            minutes: "分鐘",
            start: "開始",
            resume: "繼續",
            finished: "時間到",
            camera: "相機鏡像",
            cameraUnavailable: "無法啟動相機，請嘗試重新打開。",
            cameraHint: "在此打開即時鏡像。離開此畫面時相機會停止。",
            startCamera: "打開相機",
            stopCamera: "停止相機",
            accessories: "配件提醒",
            accessoryDescription: "顯示已連接的配件，並在電量降至20%時提醒一次。",
            connected: "已連接",
            lowBattery: "電量不足")
        case .zhHK: return NotchActivityStrings(
            timer: "計時器",
            timerDescription: "在瀏海中使用計時器和專注時段。",
            pomodoro: "番茄鐘",
            focus: "專注",
            shortBreak: "短休息",
            longBreak: "長休息",
            pomodoroHint: "專注25分鐘，休息5分鐘。每四次專注後休息15分鐘。準備好後再開始下一階段。",
            minutes: "分鐘",
            start: "開始",
            resume: "繼續",
            finished: "時間到",
            camera: "相機鏡像",
            cameraUnavailable: "無法啟動相機，請嘗試重新開啟。",
            cameraHint: "在此開啟即時鏡像。離開此畫面時相機會停止。",
            startCamera: "開啟相機",
            stopCamera: "停止相機",
            accessories: "配件提示",
            accessoryDescription: "顯示已連接的配件，並在電量降至20%時提示一次。",
            connected: "已連接",
            lowBattery: "電量不足")
        }
    }
}
