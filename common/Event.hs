{-# LANGUAGE TupleSections, FlexibleContexts #-}
module Common.Event where

-- Repa
import Data.Array.Repa (Z (..), (:.) (..))
import qualified Data.Array.Repa                 as R
import qualified Data.Array.Repa.Repr.Vector     as R

-- Gloss
import Graphics.Gloss
import Graphics.Gloss.Interface.Pure.Game

-- JuicyPixels-repa
import qualified Codec.Picture.Repa as J

-- base
import Control.Monad
import Data.Maybe
import Data.Word

-- friends
import Repa.Paths_falling_turnip

import Common.World

loadTooltip :: (Element, FilePath) -> IO (Element, R.Array R.V R.DIM2 Color)
loadTooltip (e, p) = getDataFileName p >>= \p' -> liftM ((e,) . either (error) fromJuicy) $ J.readImageRGBA p'
  where toF :: Word8 -> Float
        toF x = fromIntegral x / 255
        fromJuicy :: J.Collapsable a (Word8, Word8, Word8, Word8) => J.Img a -> R.Array R.V R.DIM2 Color
        fromJuicy = (R.computeS . flip . R.map (\(a,b,c,d) -> makeColor (toF b) (toF c) (toF d) (toF a) ) . J.collapseColorChannel)
        flip = R.backpermute (Z :. 15 :. 160) (\(Z:. y :. x) -> Z :. (14 - y) :. x )

handleInput :: Event -> World r -> World r
handleInput e w = handleInput' (w {mousePrevPos = mousePos w})
  where handleInput' world = case e of
          EventKey (MouseButton LeftButton) Down _ (x,y) -> world { mouseDown = True, mousePos = (x/factor, y/factor - palletteH) }
          EventKey (MouseButton LeftButton) Up _   (x,y) -> world { mouseDown = False, mousePos = (x/factor, y/factor - palletteH) }
          EventKey (Char 'e') Down _ _ -> world { currentElem = steam_water }
          EventKey (Char 'f') Down _ _ -> world { currentElem = fire        }
          EventKey (Char 'o') Down _ _ -> world { currentElem = oil         }
          EventKey (Char 'w') Down _ _ -> world { currentElem = water       }
          EventKey (Char 'l') Down _ _ -> world { currentElem = salt_water  }
          EventKey (Char 's') Down _ _ -> world { currentElem = sand        }
          EventKey (Char 'n') Down _ _ -> world { currentElem = salt        }
          EventKey (Char 't') Down _ _ -> world { currentElem = stone       }
          EventKey (Char 'r') Down _ _ -> world { currentElem = torch       }
          EventKey (Char 'a') Down _ _ -> world { currentElem = wall        }
          EventKey (Char 'p') Down _ _ -> world { currentElem = plant       }
          EventKey (Char 'u') Down _ _ -> world { currentElem = spout       }
          EventKey (Char 'm') Down _ _ -> world { currentElem = metal       }
          EventMotion (x,y) -> world { mousePos = (x/factor, y/factor - palletteH) }
          _ -> world

blankTooltip :: R.Array R.V R.DIM2 Color
blankTooltip = R.computeS $ R.fromFunction (Z :. 15 :. 160) (const black)

handleUI :: [(Element, R.Array R.V R.DIM2 Color)] -> GlossCoord -> World r -> World r
handleUI t p w = let tooltip = fromMaybe blankTooltip $ flip lookup t $ elemOf p
                 in if mouseDown w then
                     w {currentElem = elemOf p, tooltipLeft = tooltip
                                              , tooltipRight = tooltip }
                    else w { tooltipRight = tooltip }

