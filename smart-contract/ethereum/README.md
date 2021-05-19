** Changes for kovan testnet release

1. WETH.sol => 0xd0A1E359811322d97991E03f863a0C30C2cF029C

2. UniswapV2Factory.sol => 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f

3. Deploy UniswapV2Locker.sol (adding in uniswap factory address) => 0x44d96712044980eA7f679c26A4C24e5947e810C3

4. Deploy PresaleSettings.sol => 0x20dc5a0204eF218b055dB316689995291654B894

5. Deploy PresaleFactory.sol => 0x65852dC2c1034c14E11320d5d9e371977a174C9D

6. In PresaleLockForwarder.sol => 0x76c451bA6e3e70643AA731cEC052F853942f7507
   -- add in the constructor hardcoded PresaleFactory UniswapLocker, Uniswap factory address
   -- Deploy

7. In Presale01.sol =>
   -- Add in the constructor the hardcoded UniswapFactory, WETH, PresaleSettings, PresaleLockForwarder address, Any Dev address

8. In PresaleGenerator01.sol => 0x58e4350F9d627c6C63e3A7758C68cfEc711CB1E0
  -- Add in the constructor hardcoded PresaleFactory, PresaleSettings address
  -- deploy PresaleGenerator01.sol

9. In PresaleFactory.sol
  -- call 'adminAllowPresaleGenerator' function passing in (address PresaleGenerator01, true)

10. In UniswapV2Locker.sol
  -- call 'whitelistFeeAccount' with args (address PresaleLockForwarder, true)


** Changes for mainnet release

1. WETH.sol => 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2

2. UniswapV2Factory.sol => 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f

3. Deploy UniswapV2Locker.sol (adding in uniswap factory address) => 0x1eAfB71233164315E1eEf46c9b636861C2732801

4. Deploy PresaleSettings.sol => 0xaBAE64D9d205d0467F7cA03aA1cd133EAd41873c

5. Deploy PresaleFactory.sol => 0x35D4dc34966018Ac8c35051f86105753F4BB4AFc

6. In PresaleLockForwarder.sol => 0xE95f84F19710BeD43003e79d9ed2504E9410ed45
   -- add in the constructor hardcoded PresaleFactory UniswapLocker, Uniswap factory address
   -- Deploy

7. In Presale01.sol =>
   -- Add in the constructor the hardcoded UniswapFactory, WETH, PresaleSettings, PresaleLockForwarder address, Any Dev address

8. In PresaleGenerator01.sol => 0x72f26bbF32639479638E86FCC373599232E9f9c8
  -- Add in the constructor hardcoded PresaleFactory, PresaleSettings address
  -- deploy PresaleGenerator01.sol

9. In PresaleFactory.sol
  -- call 'adminAllowPresaleGenerator' function passing in (address PresaleGenerator01, true)

10. In UniswapV2Locker.sol
  -- call 'whitelistFeeAccount' with args (address PresaleLockForwarder, true)