// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.12;

import "../common/TransferHelper.sol";
import "../common/EnumerableSet.sol";
import "../common/SafeMath.sol";
import "../common/ReentrancyGuard.sol";
import "./IERC20.sol";

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);

    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}

interface IPresaleLockForwarder {
    function lockLiquidity(
        IERC20 _baseToken,
        IERC20 _saleToken,
        uint256 _baseAmount,
        uint256 _saleAmount,
        uint256 _unlock_date,
        address payable _withdrawer
    ) external;

    function uniswapPairIsInitialised(address token0, address token1)
        external
        view
        returns (bool);
}

interface IWETH {
    function deposit() external payable;

    function transfer(address to, uint256 value) external returns (bool);

    function withdraw(uint256) external;
}

interface IPresaleSettings {
    function getMaxPresaleLength() external view returns (uint256);

    function getBaseFee() external view returns (uint256);

    function getTokenFee() external view returns (uint256);

    function getEthAddress() external view returns (address payable);

    function getTokenAddress() external view returns (address payable);

    function getEthCreationFee() external view returns (uint256);
}

contract Presale01 is ReentrancyGuard {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct PresaleInfo {
        address payable PRESALE_OWNER;
        IERC20 S_TOKEN; // sale token
        IERC20 B_TOKEN; // base token // usually WETH (ETH)
        uint256 TOKEN_PRICE; // 1 base token = ? s_tokens, fixed price
        uint256 MAX_SPEND_PER_BUYER; // maximum base token BUY amount per account
        uint256 MIN_SPEND_PER_BUYER; // maximum base token BUY amount per account
        uint256 AMOUNT; // the amount of presale tokens up for presale
        uint256 HARDCAP;
        uint256 SOFTCAP;
        uint256 LIQUIDITY_PERCENT; // divided by 1000
        uint256 LISTING_RATE; // fixed rate at which the token will list on uniswap
        uint256 START_BLOCK;
        uint256 END_BLOCK;
        uint256 LOCK_PERIOD; // unix timestamp -> e.g. 2 weeks
        uint256 UNISWAP_LISTING_TIME;
        bool PRESALE_IN_ETH; // if this flag is true the presale is raising ETH, otherwise an ERC20 token such as DAI
    }

    struct PresaleFeeInfo {
        uint256 DAOLAUNCH_BASE_FEE; // divided by 1000
        uint256 DAOLAUNCH_TOKEN_FEE; // divided by 1000
        address payable BASE_FEE_ADDRESS;
        address payable TOKEN_FEE_ADDRESS;
    }

    struct PresaleStatus {
        bool WHITELIST_ONLY; // if set to true only whitelisted members may participate
        bool LIST_ON_UNISWAP;
        bool IS_TRANSFERED_FEE;
        bool IS_OWNER_WITHDRAWN;
        bool IS_TRANSFERED_DAOLAUNCH_FEE;
        uint256 TOTAL_BASE_COLLECTED; // total base currency raised (usually ETH)
        uint256 TOTAL_TOKENS_SOLD; // total presale tokens sold
        uint256 TOTAL_TOKENS_WITHDRAWN; // total tokens withdrawn post successful presale
        uint256 TOTAL_BASE_WITHDRAWN; // total base tokens withdrawn on presale failure
        uint256 NUM_BUYERS; // number of unique participants
    }

    struct BuyerInfo {
        uint256 baseDeposited; // total base token (usually ETH) deposited by user, can be withdrawn on presale failure
        uint256 tokensOwed; // num presale tokens a user is owed, can be withdrawn on presale success
        bool isWithdrawn;
    }

    struct GasLimit {
        uint256 transferDAOLaunchFee;
        uint256 listOnUniswap;
    }

    PresaleInfo private PRESALE_INFO;
    PresaleFeeInfo public PRESALE_FEE_INFO;
    PresaleStatus public STATUS;
    address public PRESALE_GENERATOR;
    IPresaleLockForwarder public PRESALE_LOCK_FORWARDER;
    IPresaleSettings public PRESALE_SETTINGS;
    IUniswapV2Factory public UNI_FACTORY;
    IWETH public WETH;
    mapping(address => BuyerInfo) public BUYERS;
    address payable public CALLER;
    GasLimit public GAS_LIMIT;
    address payable public DAOLAUNCH_DEV;

    modifier onlyValidAccess(uint8 _v, bytes32 _r, bytes32 _s) {
        require(isValidAccessMsg(msg.sender, _v, _r, _s));
        _;
    }
    
    function isValidAccessMsg(address _addr, uint8 _v, bytes32 _r, bytes32 _s) internal view returns(bool) {
        bytes32 hash = keccak256(abi.encodePacked(address(this), _addr));
        
        return DAOLAUNCH_DEV == ecrecover(
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)),
            _v,
            _r,
            _s
        );
    }

    constructor(address _presaleGenerator) public payable {
        PRESALE_GENERATOR = _presaleGenerator;
        UNI_FACTORY = IUniswapV2Factory(
            0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f
        );
        WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        PRESALE_SETTINGS = IPresaleSettings(
            0xaBAE64D9d205d0467F7cA03aA1cd133EAd41873c
        );
        PRESALE_LOCK_FORWARDER = IPresaleLockForwarder(
            0xE95f84F19710BeD43003e79d9ed2504E9410ed45
        );
        GAS_LIMIT = GasLimit(100000, 4000000);
        DAOLAUNCH_DEV = payable(0xE582244c3D167CFE9499b3CDA503E26CaE812E4E);
    }

    function init1(
        address payable _presaleOwner,
        uint256 _amount,
        uint256 _tokenPrice,
        uint256 _maxEthPerBuyer,
        uint256 _minEthPerBuyer,
        uint256 _hardcap,
        uint256 _softcap,
        uint256 _liquidityPercent,
        uint256 _listingRate,
        uint256 _startblock,
        uint256 _endblock,
        uint256 _lockPeriod
    ) external {
        require(msg.sender == PRESALE_GENERATOR, "FORBIDDEN");
        PRESALE_INFO.PRESALE_OWNER = _presaleOwner;
        PRESALE_INFO.AMOUNT = _amount;
        PRESALE_INFO.TOKEN_PRICE = _tokenPrice;
        PRESALE_INFO.MAX_SPEND_PER_BUYER = _maxEthPerBuyer;
        PRESALE_INFO.MIN_SPEND_PER_BUYER = _minEthPerBuyer;
        PRESALE_INFO.HARDCAP = _hardcap;
        PRESALE_INFO.SOFTCAP = _softcap;
        PRESALE_INFO.LIQUIDITY_PERCENT = _liquidityPercent;
        PRESALE_INFO.LISTING_RATE = _listingRate;
        PRESALE_INFO.START_BLOCK = _startblock;
        PRESALE_INFO.END_BLOCK = _endblock;
        PRESALE_INFO.LOCK_PERIOD = _lockPeriod;
    }

    function init2(
        IERC20 _baseToken,
        IERC20 _presaleToken,
        uint256 _DAOLaunchBaseFee,
        uint256 _DAOLaunchTokenFee,
        uint256 _uniswapListingTime,
        address payable _baseFeeAddress,
        address payable _tokenFeeAddress
    ) external {
        require(msg.sender == PRESALE_GENERATOR, "FORBIDDEN");

        PRESALE_INFO.PRESALE_IN_ETH = address(_baseToken) == address(WETH);
        PRESALE_INFO.S_TOKEN = _presaleToken;
        PRESALE_INFO.B_TOKEN = _baseToken;
        PRESALE_INFO.UNISWAP_LISTING_TIME = _uniswapListingTime;
        PRESALE_FEE_INFO.DAOLAUNCH_BASE_FEE = _DAOLaunchBaseFee;
        PRESALE_FEE_INFO.DAOLAUNCH_TOKEN_FEE = _DAOLaunchTokenFee;

        PRESALE_FEE_INFO.BASE_FEE_ADDRESS = _baseFeeAddress;
        PRESALE_FEE_INFO.TOKEN_FEE_ADDRESS = _tokenFeeAddress;
    }

    function init3(bool is_white_list, address payable _caller)
        external
    {
        require(msg.sender == PRESALE_GENERATOR, "FORBIDDEN");
        
        STATUS.WHITELIST_ONLY = is_white_list;
        CALLER = _caller;
    }

    modifier onlyPresaleOwner() {
        require(PRESALE_INFO.PRESALE_OWNER == msg.sender, "NOT PRESALE OWNER");
        _;
    }

    modifier onlyCaller() {
        require(CALLER == msg.sender, "NOT PRESALE CALLER");
        _;
    }

    function presaleStatus() public view returns (uint256) {
        if (
            (block.number > PRESALE_INFO.END_BLOCK) &&
            (STATUS.TOTAL_BASE_COLLECTED < PRESALE_INFO.SOFTCAP)
        ) {
            return 3; // FAILED - softcap not met by end block
        }
        if (STATUS.TOTAL_BASE_COLLECTED >= PRESALE_INFO.HARDCAP) {
            return 2; // SUCCESS - hardcap met
        }
        if (
            (block.number > PRESALE_INFO.END_BLOCK) &&
            (STATUS.TOTAL_BASE_COLLECTED >= PRESALE_INFO.SOFTCAP)
        ) {
            return 2; // SUCCESS - endblock and soft cap reached
        }
        if (
            (block.number >= PRESALE_INFO.START_BLOCK) &&
            (block.number <= PRESALE_INFO.END_BLOCK)
        ) {
            return 1; // ACTIVE - deposits enabled
        }
        return 0; // QUED - awaiting start block
    }

    // accepts msg.value for eth or _amount for ERC20 tokens
    function userDeposit(uint256 _amount, uint8 _v, bytes32 _r, bytes32 _s) 
        external payable onlyValidAccess(_v, _r, _s) nonReentrant  {
        require(presaleStatus() == 1, "NOT ACTIVE"); // ACTIVE

        BuyerInfo storage buyer = BUYERS[msg.sender];
        uint256 amount_in = PRESALE_INFO.PRESALE_IN_ETH ? msg.value : _amount;
        require(
            amount_in >= PRESALE_INFO.MIN_SPEND_PER_BUYER,
            "NOT ENOUGH VALUE"
        );
        uint256 allowance = PRESALE_INFO.MAX_SPEND_PER_BUYER.sub(
            buyer.baseDeposited
        );
        uint256 remaining = PRESALE_INFO.HARDCAP - STATUS.TOTAL_BASE_COLLECTED;
        allowance = allowance > remaining ? remaining : allowance;
        if (amount_in > allowance) {
            amount_in = allowance;
        }
        uint256 tokensSold = amount_in.mul(PRESALE_INFO.TOKEN_PRICE).div(
            10**uint256(PRESALE_INFO.B_TOKEN.decimals())
        );
        require(tokensSold > 0, "ZERO TOKENS");
        if (buyer.baseDeposited == 0) {
            STATUS.NUM_BUYERS++;
        }
        buyer.baseDeposited = buyer.baseDeposited.add(amount_in);
        buyer.tokensOwed = buyer.tokensOwed.add(tokensSold);
        STATUS.TOTAL_BASE_COLLECTED = STATUS.TOTAL_BASE_COLLECTED.add(
            amount_in
        );
        STATUS.TOTAL_TOKENS_SOLD = STATUS.TOTAL_TOKENS_SOLD.add(tokensSold);

        // return unused ETH
        if (PRESALE_INFO.PRESALE_IN_ETH && amount_in < msg.value) {
            msg.sender.transfer(msg.value.sub(amount_in));
        }
        // deduct non ETH token from user
        if (!PRESALE_INFO.PRESALE_IN_ETH) {
            TransferHelper.safeTransferFrom(
                address(PRESALE_INFO.B_TOKEN),
                msg.sender,
                address(this),
                amount_in
            );
        }
    }

    // withdraw presale tokens
    // percentile withdrawls allows fee on transfer or rebasing tokens to still work
    function userWithdrawTokens() external nonReentrant {
        require(presaleStatus() == 2, "NOT SUCCESS"); // SUCCESS
        require(
            STATUS.TOTAL_TOKENS_SOLD.sub(STATUS.TOTAL_TOKENS_WITHDRAWN) > 0,
            "ALL TOKEN HAS BEEN WITHDRAWN"
        );

        BuyerInfo storage buyer = BUYERS[msg.sender];

        require(!buyer.isWithdrawn, "NOTHING TO WITHDRAW");
        uint256 tokensOwed = buyer.tokensOwed;
        require(tokensOwed > 0, "NOTHING TO WITHDRAW");

        STATUS.TOTAL_TOKENS_WITHDRAWN = STATUS.TOTAL_TOKENS_WITHDRAWN.add(
            tokensOwed
        );
        TransferHelper.safeTransfer(
            address(PRESALE_INFO.S_TOKEN),
            msg.sender,
            tokensOwed
        );
        buyer.isWithdrawn = true;
    }

    // on presale failure
    // percentile withdrawls allows fee on transfer or rebasing tokens to still work
    function userWithdrawBaseTokens() external nonReentrant {
        require(presaleStatus() == 3, "NOT FAILED"); // FAILED
        BuyerInfo storage buyer = BUYERS[msg.sender];
        require(!buyer.isWithdrawn, "NOTHING TO REFUND");

        STATUS.TOTAL_BASE_WITHDRAWN = STATUS.TOTAL_BASE_WITHDRAWN.add(
            buyer.baseDeposited
        );
        TransferHelper.safeTransferBaseToken(
            address(PRESALE_INFO.B_TOKEN),
            msg.sender,
            buyer.baseDeposited,
            !PRESALE_INFO.PRESALE_IN_ETH
        );
        buyer.isWithdrawn = true;
    }

    // on presale failure
    // allows the owner to withdraw the tokens they sent for presale & initial liquidity
    function ownerRefundTokens() external onlyPresaleOwner {
        require(presaleStatus() == 3); // FAILED
        require(!STATUS.IS_OWNER_WITHDRAWN, "NOTHING TO WITHDRAW");
        TransferHelper.safeTransfer(
            address(PRESALE_INFO.S_TOKEN),
            PRESALE_INFO.PRESALE_OWNER,
            PRESALE_INFO.S_TOKEN.balanceOf(address(this))
        );
        STATUS.IS_OWNER_WITHDRAWN = true;
    }

    // on presale success, this is the final step to end the presale, lock liquidity and enable withdrawls of the sale token.
    // This function does not use percentile distribution. Rebasing mechanisms, fee on transfers, or any deflationary logic
    // are not taken into account at this stage to ensure stated liquidity is locked and the pool is initialised according to
    // the presale parameters and fixed prices.

    function listOnUniswap() external onlyCaller {
        require(
            block.number >= PRESALE_INFO.UNISWAP_LISTING_TIME,
            "Call listOnUniswap too early"
        );
        require(presaleStatus() == 2, "NOT SUCCESS"); // SUCCESS
        require(!STATUS.IS_TRANSFERED_FEE, "TRANSFERED FEE");

        uint256 DAOLaunchBaseFee = STATUS
            .TOTAL_BASE_COLLECTED
            .mul(PRESALE_FEE_INFO.DAOLAUNCH_BASE_FEE)
            .div(1000);
        // base token liquidity
        uint256 baseLiquidity = STATUS
            .TOTAL_BASE_COLLECTED
            .sub(DAOLaunchBaseFee)
            .mul(PRESALE_INFO.LIQUIDITY_PERCENT)
            .div(1000);
        if (PRESALE_INFO.PRESALE_IN_ETH) {
            WETH.deposit{value: baseLiquidity}();
        }
        TransferHelper.safeApprove(
            address(PRESALE_INFO.B_TOKEN),
            address(PRESALE_LOCK_FORWARDER),
            baseLiquidity
        );

        // // sale token liquidity
        uint256 tokenLiquidity = baseLiquidity
            .mul(PRESALE_INFO.LISTING_RATE)
            .div(10**uint256(PRESALE_INFO.B_TOKEN.decimals()));

        // transfer fees
        uint256 DAOLaunchTokenFee = STATUS
            .TOTAL_TOKENS_SOLD
            .mul(PRESALE_FEE_INFO.DAOLAUNCH_TOKEN_FEE)
            .div(1000);
        if (DAOLaunchBaseFee > 0) {
            TransferHelper.safeTransferBaseToken(
                address(PRESALE_INFO.B_TOKEN),
                PRESALE_FEE_INFO.BASE_FEE_ADDRESS,
                DAOLaunchBaseFee,
                !PRESALE_INFO.PRESALE_IN_ETH
            );
        }
        if (DAOLaunchTokenFee > 0) {
            TransferHelper.safeTransfer(
                address(PRESALE_INFO.S_TOKEN),
                PRESALE_FEE_INFO.TOKEN_FEE_ADDRESS,
                DAOLaunchTokenFee
            );
        }
        STATUS.IS_TRANSFERED_FEE = true;

        // transfer fee to DAOLaunch
        uint256 txFee = tx.gasprice.mul(GAS_LIMIT.listOnUniswap);
        require(txFee <= PRESALE_SETTINGS.getEthCreationFee());

        // // send DAOLaunch fee
        PRESALE_SETTINGS.getEthAddress().transfer(
            PRESALE_SETTINGS.getEthCreationFee().sub(txFee)
        );

        // send transaction fee
        CALLER.transfer(txFee);
        STATUS.IS_TRANSFERED_DAOLAUNCH_FEE = true;

        // Fail the presale if the pair exists and contains presale token liquidity
        if (
            PRESALE_LOCK_FORWARDER.uniswapPairIsInitialised(
                address(PRESALE_INFO.S_TOKEN),
                address(PRESALE_INFO.B_TOKEN)
            )
        ) {
            STATUS.LIST_ON_UNISWAP = true;
            return;
        }

        TransferHelper.safeApprove(
            address(PRESALE_INFO.S_TOKEN),
            address(PRESALE_LOCK_FORWARDER),
            tokenLiquidity
        );
        PRESALE_LOCK_FORWARDER.lockLiquidity(
            PRESALE_INFO.B_TOKEN,
            PRESALE_INFO.S_TOKEN,
            baseLiquidity,
            tokenLiquidity,
            block.timestamp + PRESALE_INFO.LOCK_PERIOD,
            PRESALE_INFO.PRESALE_OWNER
        );
        STATUS.LIST_ON_UNISWAP = true;
    }

    function ownerWithdrawTokens() external nonReentrant onlyPresaleOwner {
        require(!STATUS.IS_OWNER_WITHDRAWN, "GENERATION COMPLETE");
        require(presaleStatus() == 2, "NOT SUCCESS"); // SUCCESS

        uint256 DAOLaunchBaseFee = STATUS
            .TOTAL_BASE_COLLECTED
            .mul(PRESALE_FEE_INFO.DAOLAUNCH_BASE_FEE)
            .div(1000);
        uint256 baseLiquidity = STATUS
            .TOTAL_BASE_COLLECTED
            .sub(DAOLaunchBaseFee)
            .mul(PRESALE_INFO.LIQUIDITY_PERCENT)
            .div(1000);
        uint256 DAOLaunchTokenFee = STATUS
            .TOTAL_TOKENS_SOLD
            .mul(PRESALE_FEE_INFO.DAOLAUNCH_TOKEN_FEE)
            .div(1000);
        uint256 tokenLiquidity = baseLiquidity
            .mul(PRESALE_INFO.LISTING_RATE)
            .div(10**uint256(PRESALE_INFO.B_TOKEN.decimals()));

        // send remain unsold tokens to presale owner
        uint256 remainingSBalance = PRESALE_INFO
            .S_TOKEN
            .balanceOf(address(this))
            .add(STATUS.TOTAL_TOKENS_WITHDRAWN)
            .sub(STATUS.TOTAL_TOKENS_SOLD);

        // send remaining base tokens to presale owner
        uint256 remainingBaseBalance = PRESALE_INFO.PRESALE_IN_ETH
            ? address(this).balance
            : PRESALE_INFO.B_TOKEN.balanceOf(address(this));
        if (!STATUS.IS_TRANSFERED_FEE) {
            remainingBaseBalance = remainingBaseBalance.sub(DAOLaunchBaseFee);
            remainingSBalance = remainingSBalance.sub(DAOLaunchTokenFee);
        }
        if (!STATUS.LIST_ON_UNISWAP) {
            remainingBaseBalance = remainingBaseBalance.sub(baseLiquidity).sub(
                PRESALE_SETTINGS.getEthCreationFee()
            );
            remainingSBalance = remainingSBalance.sub(tokenLiquidity);
        }

        if (remainingSBalance > 0) {
            TransferHelper.safeTransfer(
                address(PRESALE_INFO.S_TOKEN),
                PRESALE_INFO.PRESALE_OWNER,
                remainingSBalance
            );
        }

        TransferHelper.safeTransferBaseToken(
            address(PRESALE_INFO.B_TOKEN),
            PRESALE_INFO.PRESALE_OWNER,
            remainingBaseBalance,
            !PRESALE_INFO.PRESALE_IN_ETH
        );
        STATUS.IS_OWNER_WITHDRAWN = true;
    }

    function sendDAOLaunchFee() external onlyCaller {
        require(
            !STATUS.IS_TRANSFERED_DAOLAUNCH_FEE,
            "IS_TRANSFERED_DAOLAUNCH_FEE"
        );
        require(presaleStatus() == 3, "NOT FAILED"); // FAILED

        // calcucalte transaction fee
        uint256 txFee = tx.gasprice.mul(GAS_LIMIT.transferDAOLaunchFee);
        require(txFee <= PRESALE_SETTINGS.getEthCreationFee());

        // send DAOLaunch fee
        PRESALE_SETTINGS.getEthAddress().transfer(
            PRESALE_SETTINGS.getEthCreationFee().sub(txFee)
        );

        // send transaction fee
        CALLER.transfer(txFee);
        STATUS.IS_TRANSFERED_DAOLAUNCH_FEE = true;
    }

    function updateGasLimit(
        uint256 _transferDAOLaunchFee,
        uint256 _listOnUniswap
    ) external onlyPresaleOwner {
        GAS_LIMIT.transferDAOLaunchFee = _transferDAOLaunchFee;
        GAS_LIMIT.listOnUniswap = _listOnUniswap;
    }

    function updateMaxSpendLimit(uint256 _maxSpend) external onlyPresaleOwner {
        PRESALE_INFO.MAX_SPEND_PER_BUYER = _maxSpend;
    }

    // postpone or bring a presale forward, this will only work when a presale is inactive.
    // i.e. current start block > block.number
    function updateBlocks(uint256 _startBlock, uint256 _endBlock)
        external
        onlyPresaleOwner
    {
        require(PRESALE_INFO.START_BLOCK > block.number);
        require(_endBlock.sub(_startBlock) > 0);
        PRESALE_INFO.START_BLOCK = _startBlock;
        PRESALE_INFO.END_BLOCK = _endBlock;
    }

    // if uniswap listing fails, call this function to release eth
    function finalize() external {
        require(msg.sender == DAOLAUNCH_DEV, "INVALID CALLER");
        selfdestruct(DAOLAUNCH_DEV);
    }
}
