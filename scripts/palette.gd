class_name Palette
extends RefCounted
## Цветовая палитра игры (Happy Hues, тёмно-зелёная). Используется и в 3D-мире,
## и в интерфейсе; те же цвета заданы в теме интерфейса ui/theme.tres.

const BACKGROUND := Color("#004643")  ## Фон, панели.
const HEADLINE := Color("#fffffe")    ## Заголовки.
const PARAGRAPH := Color("#abd1c6")   ## Основной текст.
const HIGHLIGHT := Color("#f9bc60")   ## Акцент: кнопки, цель (жёлто-оранжевый).
const STROKE := Color("#001e1d")      ## Обводка, текст на кнопках.
const MAIN := Color("#e8e4e6")        ## Светлые поверхности.
const SECONDARY := Color("#abd1c6")   ## Вторичный: мятный.
const TERTIARY := Color("#e16162")    ## Третичный: коралловый.

## Цвета сообщений на тёмной панели.
const OK := Color("#abd1c6")
const ERROR := Color("#ff8f90")
const HINT := Color("#f9bc60")
