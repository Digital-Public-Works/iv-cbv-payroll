import autoprefixer from "autoprefixer"
import postcssMinify from "postcss-minify"

export const config = {
  plugins: [autoprefixer, process.env.NODE_ENV === "production" ? postcssMinify : null].filter(
    Boolean
  ),
}

export default config
