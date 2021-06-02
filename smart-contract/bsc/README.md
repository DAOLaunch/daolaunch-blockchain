** Changes for testnet release

1. WETH.sol => 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd

2. UniswapV2Factory.sol => 0x6725F303b657a9451d8BA641348b6761A6CC7a17

3. Deploy UniswapV2Locker.sol (adding in uniswap factory address) => 0xb8B7ff8319247200279F879A6e1aA7FDD08921db

4. Deploy BSCPresaleSettings.sol => 0xE0008E1182d7711fc7732c78D76a05867cd49F6e

5. Deploy PresaleFactory.sol => 0x738aA021145E8b2B9e147312f06376b7d5597552

6. In PresaleLockForwarder.sol => 0x059F5bbf83773e6ECB7c4510fA01Cad3B4950e1d
   -- add in the constructor hardcoded PresaleFactory UniswapLocker, Uniswap factory address
   -- Deploy

7. In Presale01.sol =>
   -- Add in the constructor the hardcoded UniswapFactory, WETH, PresaleSettings, PresaleLockForwarder address, Any Dev address

8. In PresaleGenerator01.sol => 0x803F10d75BE1f020F19450eE0F6C7118F5eE2713
  -- Add in the constructor hardcoded PresaleFactory, PresaleSettings address
  -- deploy PresaleGenerator01.sol

9. In PresaleFactory.sol
  -- call 'adminAllowPresaleGenerator' function passing in (address PresaleGenerator01, true)

10. In UniswapV2Locker.sol
  -- call 'whitelistFeeAccount' with args (address PresaleLockForwarder, true)

** Changes for mainnet release

1. WETH.sol => 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c

2. UniswapV2Factory.sol => 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73

3. Deploy UniswapV2Locker.sol (adding in uniswap factory address) => 0xD62b8296E293EA793f8bAB4407FD8B67D8Fd6aCA

4. Deploy BSCPresaleSettings.sol => 0xF8DA618A73dd5bb2dd4bBf69961192F7A32533ef

5. Deploy PresaleFactory.sol => 0xD2fc87C398D2e93d852830a1688D6E5E42281489

6. In PresaleLockForwarder.sol => 0x5D7Adaa470eb4aCc45991d58A70e0008e87b7909
   -- add in the constructor hardcoded PresaleFactory UniswapLocker, Uniswap factory address
   -- Deploy

7. In Presale01.sol =>
   -- Add in the constructor the hardcoded UniswapFactory, WETH, PresaleSettings, PresaleLockForwarder address, Any Dev address

8. In PresaleGenerator01.sol => 0x0f5475405c120557A848971A65Ad0AfA088d8F2e
  -- Add in the constructor hardcoded PresaleFactory, PresaleSettings address
  -- deploy PresaleGenerator01.sol

9. In PresaleFactory.sol
  -- call 'adminAllowPresaleGenerator' function passing in (address PresaleGenerator01, true)

10. In UniswapV2Locker.sol
  -- call 'whitelistFeeAccount' with args (address PresaleLockForwarder, true)